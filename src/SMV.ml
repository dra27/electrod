(*******************************************************************************
 * electrod - a model finder for relational first-order linear temporal logic
 * 
 * Copyright (C) 2016-2018 ONERA
 * Authors: Julien Brunel (ONERA), David Chemouil (ONERA)
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * SPDX-License-Identifier: MPL-2.0
 * License-Filename: LICENSES/MPL-2.0.txt
 ******************************************************************************)

open Containers



let nuXmv_default_script = [%blob "../res/nuxmv-default-script.txt"]

let nuSMV_default_script = [%blob "../res/nusmv-default-script.txt"]


module Make_SMV_LTL (At : Solver.ATOMIC_PROPOSITION)
  : Solver.LTL with module Atomic = At = struct
  module I = Solver.LTL_from_Atomic(At) 

  include I

  module PP = struct
    open Fmtc
    
    let rainbow =
      let r = ref 0 in
      fun () ->
        let cur = !r in
        incr r;
        match cur with
          | 0 -> `Magenta
          | 1 -> `Yellow
          | 2 -> `Cyan
          | 3 -> `Green
          | 4 -> `Red
          | 5 -> r := 0; `Blue
          | _ -> assert false

    (* [upper] is the precedence of the context we're in, [this] is the priority
       for printing to do, [pr] is the function to make the printing of the
       expression *)
    let rainbow_paren ?(paren = false) ?(align_par = true)
          upper this out pr =
      (* parenthesize if specified so or if  forced by the current context*)
      let par = paren || this < upper in
      (* if parentheses are specified, they'll be numerous so avoid alignment of
         closing parentheses *)
      (* let align_par = not paren && align_par in *)
      if par then               (* add parentheses *)
        let color = rainbow () in
        if align_par then
          Format.pp_open_box out 0
        else
          Format.pp_open_box out 2;
        styled color string out "(";
        if align_par then Format.pp_open_box out 2;
        (* we're adding parentheses so precedence goes back to 0 inside of
           them *)
        pr 0;
        if align_par then 
          begin
            Format.pp_close_box out ();
            cut out ()
          end ;
        styled color string out ")";
        Format.pp_close_box out ()
      else                      (* no paremtheses *)
        (* so keep [this] precedence *)
        pr this
      
    let infixl ?(paren = false) ?(align_par = true)
          upper this middle left right out (m, l, r) =
      rainbow_paren ~paren ~align_par upper this out @@
      fun new_this ->      (* new_this is this or 0 if parentheses were added *)
      begin
        left new_this out l;
        sp out ();
        styled `Bold middle out m;
        sp out ();
        right (new_this + 1) out r (* left associativity => increment the precedence *)
      end
                    

    let infixr ?(paren = false) ?(align_par = true)
          upper this middle left right out (m, l, r) =
      rainbow_paren ~paren ~align_par upper this out @@
      fun new_this ->
      begin
        left (new_this + 1) out l;
        sp out ();
        styled `Bold middle out m;
        sp out ();
        right new_this out r
      end

    let infixn ?(paren = false) ?(align_par = true)
          upper this middle left right out (m, l, r) =
      rainbow_paren ~paren ~align_par upper this out @@
      fun new_this ->
      begin
        left (new_this + 1) out l;
        sp out ();
        styled `Bold middle out m;
        sp out ();
        right (new_this + 1) out r
      end

    let prefix ?(paren = false) ?(align_par = true)
          upper this pprefix pbody out (prefix, body) =
      rainbow_paren ~paren ~align_par upper this out @@
      fun new_this ->
      begin
        styled `Bold pprefix out prefix;
        pbody (new_this + 1) out body
      end
                    
    type atomic = At.t

    let pp_atomic = At.pp

    let pp_tcomp out (t : tcomp) =
      pf out "%s"
      @@ match t with
      | Lte  -> "<="
      | Lt  -> "<"
      | Gte  -> ">="
      | Gt  -> ">"
      | Eq  -> "="
      | Neq  -> "!="

    let styled_parens st ppv_v out v =
      surround (styled st lparen) (styled st rparen) ppv_v out v
    


    (* From NuXmv documentation, from high to low (excerpt, some precedences are ignored because they are not used)

       !

       - (unary minus)

       + -

       = != < > <= >=

       &

       | xor xnor

       (... ? ... : ...)

       <->

       -> (the only right associative op)

    
NOTE: precedences for LTL connectives are not specified, hence we force parenthesising of these.
*)

    let pp ?(next_is_X = true) variables upper out f =
      let rec pp upper out f =
        assert (upper >= 0);
        match f with
          | True  -> pf out "TRUE"
          | False  -> pf out "FALSE"
          | Atomic at -> 
              begin
                variables := Sequence.cons at !variables;
                pf out "%a" pp_atomic at
              end
          (* tweaks, here, to force parenthese around immediate subformulas of Imp
             and Iff as their precedence may not be easily remembered*)
          | Imp (p, q) -> infixr ~paren:true upper 1 string pp pp out ("->", p, q)
          | Iff (p, q) -> infixl ~paren:true upper 2 string pp pp out ("<->", p, q)
          | Ite (c, t, e) ->
              (* SMV's ...?...:... or case...esac expression cannot be
                 used as nuXmv does not accept these when subexpressions
                 are temporal (seen invarious tests). So we rewrite the formula into more basic terms. *)
              pp upper out @@ I.Infix.((c @=> lazy t) +&& lazy ((I.not_ c) @=> lazy e))
          | Or (p, q) -> infixl ~paren:true upper 4 string pp pp out ("|", p, q)
          (* force parenthses as we're not used to see the Xor connective and so its precedence may be unclear *)
          | Xor (p, q) -> infixl ~paren:true upper 4 string pp pp out ("xor", p, q)
          | And (p, q) -> infixl ~paren:true upper 5 string pp pp out ("&", p, q)
          | Comp (op, t1, t2) ->
              infixn upper 6 pp_tcomp pp_term pp_term out (op, t1, t2)
          | Not p -> prefix upper 9 string pp out ("!", p)
          (* no known precedence for temporal operators so we force parentheses and
             use as the "this" precedence that of the upper context*)
          | U (p, q) -> infixl ~paren:true upper upper string pp pp out ("U", p, q)
          | R (p, q) -> infixl ~paren:true upper upper string pp pp out ("V", p, q)
          | S (p, q) -> infixl ~paren:true upper upper string pp pp out ("S", p, q)
          | T (p, q) -> infixl ~paren:true upper upper string pp pp out ("T", p, q)
          | X p when next_is_X -> prefix ~paren:true upper upper string pp out ("X ", p)
          | X p ->  (* next_is _X= false *)
              begin
                styled `Bold string out "next";
                pf out "@[(%a@])" (pp 0) p
              end
          | F p -> prefix ~paren:true upper upper string pp out ("F ", p)
          | G p -> prefix ~paren:true upper upper string pp out ("G ", p)
          | Y p -> prefix ~paren:true upper upper string pp out ("Y ", p)
          | O p -> prefix ~paren:true upper upper string pp out ("O ", p)
          | H p -> prefix ~paren:true upper upper string pp out ("H ", p)

      and pp_term upper out (t : term) = match t with
        | Num n -> pf out "%d" n
        | Plus (t1, t2) ->
            infixl ~paren:true upper 7 string pp_term pp_term out ("+", t1, t2)
        | Minus (t1, t2) ->
            infixl ~paren:true upper 7 string pp_term pp_term out ("-", t1, t2)
        | Neg t -> prefix upper 8 string pp_term out ("- ", t)
        | Count ts ->
            styled `Bold string out "count";            
            pf out "@[(%a@])" (list ~sep:(const string ", ") (pp 0)) ts

      in pp upper out f
  end

  let pp_atomic = PP.pp_atomic

  let pp_gather_variables ?(next_is_X = true) variables out f =
    Fmtc.pf out "@[<hov2>%a@]" (PP.pp ~next_is_X variables 0) f

  let pp out f =
    pp_gather_variables (ref Sequence.empty) out f


  (* let () =  *)
  (*   begin *)
  (*     let p = atomic @@ make_atomic (Name.name "P") (Tuple.of_list1 [Atom.atom "p"]) in *)
  (*     let q = atomic @@ make_atomic (Name.name "Q") (Tuple.of_list1 [Atom.atom "q"]) in *)
  (*     let r = atomic @@ make_atomic (Name.name "R") (Tuple.of_list1 [Atom.atom "r"]) in *)
  (*     let s = atomic @@ make_atomic (Name.name "S") (Tuple.of_list1 [Atom.atom "s"]) in *)
  (*     let f1 = and_ (and_ p @@ lazy q) (lazy r) in *)
  (*     let f2 = implies (and_ p @@ lazy q) (lazy r) in *)
  (*     let f3 = implies r (lazy (and_ p @@ lazy q)) in *)
  (*     let f4 = implies (and_ p @@ lazy q) (lazy (and_ r (lazy s))) in *)
  (*     let f5 = and_ (implies p @@ lazy q) (lazy (implies r @@ lazy s)) in *)
  (*     let f6 = implies p (lazy (and_ (implies q @@ lazy r) (lazy (implies r @@ lazy s)))) in *)
  (*     let f7 = implies p (lazy (and_ (implies (and_ q (lazy p)) @@ lazy r) (lazy (implies r @@ lazy s)))) in *)
  (*     Fmt.epr "TEST PP@\n"; *)
  (*     Fmt.epr "and_ (and_ p @@ lazy q) (lazy r) -->@  %a@\n" pp f1; *)
  (*     Fmt.epr "implies (and_ p @@ lazy q) (lazy r) -->@  %a@\n" pp f2; *)
  (*     Fmt.epr "implies r (lazy (and_ p @@ lazy q)) -->@  %a@\n" pp f3; *)
  (*     Fmt.epr "implies (and_ p @@ lazy q) (lazy (and_ r (lazy s))) -->@  %a@\n" pp f4; *)
  (*     Fmt.epr "and_ (implies_ p @@ lazy q) (implies_ r @@ lazy s) -->@  %a@\n" pp f5; *)
  (*     Fmt.epr "implies p (lazy (and_ (implies q @@ lazy r) (lazy (implies r @@ lazy s)))) -->@  %a@\n" pp f6; *)
  (*     Fmt.epr "implies p (lazy (and_ (implies (and_ q (lazy p)) @@ lazy r) (lazy (implies r @@ lazy s)))) -->@  %a@\n" pp f7; *)
      
  (*     flush_all () *)
  (*   end *)

  
end

module Make_SMV_file_format (Ltl : Solver.LTL)
  : Solver.MODEL with type ltl = Ltl.t and type atomic = Ltl.Atomic.t = struct

  type ltl = Ltl.t

  type atomic = Ltl.Atomic.t

  type t = {
      elo : Elo.t;
      init : (string * ltl) Sequence.t;
      invariant : (string * ltl) Sequence.t;
      trans : (string * ltl) Sequence.t;
      property : string * ltl 
    }

  let make ~elo ~ init ~invariant ~trans ~property =
    { elo ; init = init ; invariant = invariant ; trans = trans ; property }

  let pp_plain_decl vartype out atomic =
    Fmtc.pf out "%s %a : boolean;" vartype Ltl.Atomic.pp atomic

  (* for an enumerated declaration, all the may corresponding to the name must
     be created, even if some cases were cancelled out when printing
     formulas. Indeed, the enumeration also represents a typing invariant which
     would have been a formula too, one that would have spoken about all the
     part. Besides, for 'lone' relations a special value representing the
     absence must be added. *)
  let pp_enum_decl elo vartype out atoms =
    let module S = Sequence in
    let tuple_to_string tuple =
      Fmtc.(strf "%a" @@ list ~sep:minus Atom.pp) (Tuple.to_list tuple)
    in
    let atom_name at = Option.get_exn @@ Ltl.Atomic.split at in
    let pp_one_decl atom =
      let name, _ = atom_name atom in
      let name_str = Name.to_string name in
      (* To avoid changin the generation of LTL formulas, we generate DEFINEs of
         the form `DEFINE x_a1_b1 := x_a1 = b1` (for x of domain arity 1) *)
      let may = Domain.may name elo.Elo.domain |> TupleSet.to_seq in
      (* where to split tuples (if necessary)? *)
      let dom_ar = Ltl.Atomic.domain_arity atom in
      match dom_ar with
        | None -> assert false
        | Some n when n < 0 -> assert false
        | Some 0 ->             (* an enumerated set *)
            begin
              let may_strings =
                S.map tuple_to_string may in
              (* add a value for none? *)
              let may_strings_with_empty =
                if Ltl.Atomic.is_partial atom then
                  (* add __NONE__ at the end (better for SMV boolean encoding) *)
                  S.snoc may_strings "__NONE__" 
                else may_strings
              in
              S.iter (fun tuple_str ->
                    Fmtc.(
                      pf out "DEFINE %s-%s := __%s = %s;@\n"
                        name_str
                        tuple_str
                        name_str
                        tuple_str
                    )
                  )
                may_strings;
              Fmtc.(
                pf out "%s __%s : %a;@\n"
                  vartype
                  name_str
                  (braces_ @@ S.pp_seq string) may_strings_with_empty
              )
            end
        | Some n -> (* a partial or total function with domain arity n > 0 *)
            begin
              (* first we split all tuples depending on the arity, and regroup
                 them in lists of pairs (dom, range) with the same dom *)
              let domains_ranges =
                may
                |> S.map
                     (fun tuple ->
                        Pair.map_same tuple_to_string @@ Tuple.split tuple n)
                |> S.group_by
                     ~hash:(fun (dom, _) -> Hash.string dom)
                     ~eq:(fun (dom1, _) (dom2, _) -> String.equal dom1 dom2)
              in
              (* Msg.debug (fun m ->
               *       m "domains_Ranges = @[<v>%a@]"
               *         Fmtc.(brackets_ @@ S.pp_seq
               *               @@ brackets @@ list ~sep:comma
               *               @@ pair string string) domains_ranges
               *     ); *)
              (* print the DEFINEs *)
              S.iter
                (fun pairs ->
                   List.iter
                     (fun (dom_str, range_str) ->
                        Fmtc.(
                          pf out "DEFINE %s-%s-%s := __%s-%s = %s;@\n"
                            name_str
                            dom_str
                            range_str
                            name_str
                            dom_str
                            range_str                      
                        )
                     ) pairs
                )
                domains_ranges;
              (* now print the vars: we walk along the lists of pairs (dom,
                 range) (where every dom is the same) and we use the range to create
                 `VAR x_dom : { ... range ...}`  *)
              S.iter
                (fun pairs ->
                   let dom_str = fst @@ List.hd pairs in
                   Fmtc.(
                     pf out "%s __%s-%s : %a;@\n"
                       vartype 
                       name_str
                       dom_str
                       (braces_ @@ box @@ list ~sep:(sp **> comma) string)
                       (if Ltl.Atomic.is_partial atom then
                          List.rev ("__NONE__" :: List.rev_map snd pairs)
                        else
                          List.map snd pairs)
                   ))
                domains_ranges
            end
    in
    atoms
    |> S.sort_uniq      (* keep only atoms with different relation names *)
         ~cmp:(fun at1 at2 ->
               Name.compare (fst @@ atom_name at1) (fst @@ atom_name at2))
    |> S.iter (fun at -> Fmtc.hardline out (); pp_one_decl at)

  let pp_count_variables ?(margin = 80) out { elo; init; invariant; trans; property } =
    let open Fmtc in
    let module S = Sequence in
    (* to gather the variables along printing in the buffer *)
    let variables = ref S.empty in
    let old_margin = Format.pp_get_margin out () in
    Format.pp_set_margin out margin;
    pf out
      "-- Generated by electrod (C) ONERA 2016-2018@\n\
       MODULE main@\n\
       JUSTICE TRUE;@\n@\n";
    (* INIT *)
    Format.pp_open_vbox out 0;
    S.iter
      (fun (elo_str, fml) -> 
         pf out "%s@\nINIT@\n@[<hv2>%a@];@\n@\n"
           elo_str
           (Ltl.pp_gather_variables variables) fml)
      init;
    Format.pp_close_box out ();
    (* INVAR *)
    Format.pp_open_vbox out 0;
    S.iter
      (fun (elo_str, fml) -> 
         pf out "%s@\nINVAR@\n@[<hv2>%a@];@\n@\n"
           elo_str
           (Ltl.pp_gather_variables variables) fml)
      invariant;
    Format.pp_close_box out ();
    (* TRANS *)
    Format.pp_open_vbox out 0;
    S.iter
      (fun (elo_str, fml) -> 
         pf out "%s@\nTRANS@\n@[<hv2>%a@];@\n@\n"
           elo_str
           (Ltl.pp_gather_variables ~next_is_X:false variables) fml)
      trans;
    Format.pp_close_box out (); 
    (* SPEC *)
    Format.pp_open_vbox out 0;
    let prop_str, ltlspec = property in
    pf out "%s@\nLTLSPEC@\n@[<hv2>%a@];@\n@\n"
      prop_str
      (Ltl.pp_gather_variables variables)
      ltlspec;
    Format.pp_close_box out ();

    (* HANDLING VARIABLES *)
    (* sorting before filtering (even when sorting after again) is more
       efficient on a few tests *)
    let sort_atomics atoms = S.sort_uniq ~cmp:Ltl.Atomic.compare atoms in
    variables := sort_atomics !variables;
    (* filter variables on frozen/var and plain/enum *)
    let r_plain, r_enum, f_plain, f_enum =
      S.fold
        (fun (acc_rp, acc_re, acc_fp, acc_fe) at ->
           if Ltl.Atomic.is_const at then (* rigid *)
             if Ltl.Atomic.domain_arity at = None then (* plain *)
               (S.cons at acc_rp, acc_re, acc_fp, acc_fe)
             else               (* enumerable *)
               (acc_rp, S.cons at acc_re, acc_fp, acc_fe)
           else             (* flexible *)
             if Ltl.Atomic.domain_arity at = None then (* plain *)
               (acc_rp, acc_re, S.cons at acc_fp, acc_fe)
             else               (* enumerable *)
               (acc_rp, acc_re, acc_fp, S.cons at acc_fe))
        (S.empty, S.empty, S.empty, S.empty)
        !variables
      |> fun (res_rp, res_re, res_fp, res_fe) ->
      (sort_atomics res_rp, res_re, sort_atomics res_fp, res_fe)
    in
    (* FROZENVAR / PLAIN *)
    S.iter (fun at -> pf out "%a@\n" (pp_plain_decl "FROZENVAR") at) r_plain;
    (* FROZENVAR / ENUM *)
    pp_enum_decl elo "FROZENVAR" out r_enum;
    
    (* VAR / PLAIN *)
    (if not (S.is_empty r_plain || S.is_empty f_plain) then hardline out ());
    S.iter (fun at -> pf out "%a@\n" (pp_plain_decl "VAR") at) f_plain;
    
    (* VAR / ENUM *)
    pp_enum_decl elo "VAR" out f_enum;
    
    (* close printing *)    
    Format.pp_print_flush out ();
    Format.pp_set_margin out old_margin;

    (* return the number of variables *)
    S.length !variables


  let pp ?(margin = 80) out { elo; init; invariant; trans; property } =
    ignore (pp_count_variables ~margin out { elo; init; invariant; trans; property })
  
  (* write in temp file *)
  let make_model_file dir infile model =
    let src_file = Filename.basename infile in
    let tgt = Filename.temp_file ~temp_dir:dir (src_file ^ "-") ".smv" in
    let nbvars = ref 0 in
    IO.with_out tgt 
      (fun out ->
          nbvars := pp_count_variables (Format.formatter_of_out_channel out) model);
    (tgt, !nbvars)

  
  let make_script_file dir = function
    | Solver.File filename -> filename (* script given on the command line *)
    | Solver.Default default ->
        let tgt = Filename.temp_file ~temp_dir:dir "electrod-" ".scr" in
        IO.with_out tgt (fun out -> IO.write_line out default);
        tgt
  
  (* TODO pass script as argument *)
  (* TODO allow to specify a user script *)
  let analyze ~conversion_time ~cmd ~script ~keep_files
        ~no_analysis ~elo ~file model : Outcome.t=
    let keep_or_remove_files scr smv =
      if keep_files then
        begin
          if no_analysis then
            Logs.app
              (fun m ->
                 m "@[<hv2>Keeping the script and SMV files at:@ %s@\n%s@]"
                   scr smv)
          else 
            Logs.app
              (fun m ->
                 m "@[<hv2>Keeping the script and SMV files@]")
        end
      else begin
        (match script with
          | Solver.Default _ -> IO.File.remove_noerr scr
          | Solver.File _ -> ());
        IO.File.remove_noerr smv
      end
    in
    (* TODO check whether nuXmv is installed first *)
    let dir =
      if keep_files then Filename.dirname file
      else Filename.get_temp_dir_name ()
    in
    let scr = make_script_file dir script in
    let before_generation = Mtime_clock.now () in
    let smv, nbvars = make_model_file dir file model in
    let after_generation = Mtime_clock.now () in
    Msg.info (fun m ->
          let size, unit_ =
            let s = float_of_int @@ Unix.((stat smv).st_size) in
            if s < 1_024. then
              (s, "B")
            else if s < 1_048_576. then
              (s /. 1_024., "KB")
            else if s < 1_073_741_824. then
              (s /. 1_048_576., "MB")
            else
              (s /. 1_073_741_824., "GB")
          in
          m "SMV file (size: %.0f%s) generated in %a"
            (Float.round size) unit_
            Mtime.Span.pp (Mtime.span before_generation after_generation));
    if no_analysis then begin
      keep_or_remove_files scr smv;
      Outcome.no_trace nbvars conversion_time Mtime.Span.zero
    end
    else
      (* TODO make things s.t. it's possible to set a time-out *)
      let to_call = Fmt.strf "%s -source %s %s" cmd scr smv in
      Logs.app (fun m -> m "Starting analysis:@[<h2>@ %s@]" to_call);
      let before_run = Mtime_clock.now () in
      let (okout, errout, errcode) =
        CCUnix.call "%s" to_call
      in
      let after_run = Mtime_clock.now () in
      let analysis_time = Mtime.span before_run after_run in
      if errcode <> 0 then
        Msg.Fatal.solver_failed (fun args -> args cmd scr smv errcode errout)
      else (* running nuXmv goes well: parse its output *)
        Msg.info (fun m -> m "Analysis done in %a" Mtime.Span.pp
                             analysis_time );
      let spec =
        String.lines_gen okout
        |> Gen.drop_while
             (fun line ->
                not @@ String.suffix ~suf:"is false" line
                && not @@ String.suffix ~suf:"is true" line)
      in
      keep_or_remove_files scr smv;

      if String.suffix ~suf:"is true" @@ Gen.get_exn spec then
        Outcome.no_trace nbvars conversion_time analysis_time
      else
        (* nuXmv says there is a counterexample so we parse it on the standard
           output *)
        (* first create a trace parser (it is parameterized by [base] below
           which tells the parser the "must" associated to every relation in the
           domain, even the ones not present in the SMV file because they have
           been simplified away in the translation. This goes this way because
           the trace to return should reference all relations, not just the ones
           grounded in the SMV file.). NOTE: the parser expects a nuXmv trace
           using the "trace plugin" number 1 (classical output (i.e. no XML, no
           table) with information on all variables, not just the ones that have
           changed w.r.t. the previous state.). *)
        let module P =
          SMV_trace_parser.Make(struct
            let base = Domain.musts ~with_univ_and_ident:false elo.Elo.domain
          end)
        in
        let trace =
          spec
          (* With this trace output, nuXmv shows a few uninteresting lines first,
             that we have to gloss over *)
          |> Gen.drop_while (fun line -> not @@ String.prefix ~pre:"Trace" line)
          |> Gen.drop_while (String.prefix ~pre:"Trace")
          |> String.unlines_gen
          (* |> Fun.tap print_endline *)
          |> fun trace_str ->
          (let lexbuf = Lexing.from_string trace_str in
           (P.trace (SMV_trace_scanner.main Ltl.Atomic.split_string) lexbuf))
        in
        if not @@ Outcome.loop_is_present trace then
          Msg.Fatal.solver_bug (fun args ->
                args cmd "trace is missing a loop state.")
        else
          Outcome.trace nbvars conversion_time analysis_time trace
        
  end
