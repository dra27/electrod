
{ (* BEGIN HEADER *)

  
open Lexing
open Parser

} (* END HEADER *)


let newline = ('\010' | '\013' | "\013\010")

let whitespace = [ ' ' '\t' ]

let digit = [ '0'-'9' ]

let number = (digit | [ '1'-'9'] digit*)
                           
let letter = [ 'A'-'Z' 'a'-'z' ]

let dollar = '$'

let plain_id = letter (letter | digit | '_')*

let idx_id = plain_id dollar number

let pragma = "##" plain_id

let comment_line = ("--")

let reserved_symbol = [ '$' '%' '\\' '`' '@' ]

let builtin_iop = ( "add" | "neg" | "minus" | "card" )
                  
let builtin_rop = ( "")
                  
let builtin_pred = ( "totalOrder" )
                 
rule main infile = parse
| reserved_symbol as c
  { Msg.Fatal.lexical
    @@ fun args -> args infile lexbuf (Printf.sprintf "reserved character: '%c'" c)}
| newline
    { new_line lexbuf; main infile lexbuf }
| whitespace+
    { main infile lexbuf }
| number as i
    {
      try
        (NUMBER (int_of_string i))
      with Failure _ ->
        Msg.Fatal.lexical
        @@ fun args -> args infile lexbuf ("invalid integer constant '" ^ i ^ "'")
    }   
| "unsat" 
    { Msg.Fatal.lexical
      @@ fun args -> args infile lexbuf (Printf.sprintf "reserved keyword: 'unsat'")}
| "sat"
    { SAT }
(*| "int"
      { INT }*)
| "true"
		{ TRUE }
| "false"
		{ FALSE }
                    (* FUTURE OPERATORS *)
| "next"
    { NEXT }
| "always"
    { ALWAYS }
| ("sometime")
    { SOMETIME }
| "until"
    { UNTIL }
                    (* PAST OPERATORS *)
| "previous"
    { PREVIOUS }
| "historically"
    { HISTORICALLY }
| "once"
    { ONCE }
| "since"
    { SINCE }
                    (* F-O QUANTIFIERS + MULTIPLICITIES *)
| "all"
    { ALL }
| "some"
    { SOME }
| "one"
    { ONE }
(*| "set"
    { SET }*)
| "no"
    { NO }
| "lone"
    { LONE }
| "let"
    { LET }
| "disj"
    { DISJ }
| ("iff")
    { IFF }
| ("implies")
    { IMPLIES }
| "then"
  { THEN }
| "else"
    { ELSE }
| ("or")
    { OR }
| ("and")
    { AND }
| "in"
    { IN }
| "not" (whitespace | newline)+ "in" (* TODO: take comments into account *)
    { NOT_IN}
| "in"
    { IN }
| ("not")
    { NOT }
| "var"
    { VAR }
| "const"
    { CONST }
| "univ"
    { UNIV }
| "iden"
    { IDEN }
| "none"
    { NONE }
| builtin_pred as b
  { FBUILTIN b }
| idx_id as id
    { (IDX_ID id) }
| plain_id as id
  { (PLAIN_ID id) }
| "#"
  { HASH }
| "!="
    { NEQ }
| "'"
    { PRIME }
| ";"
    { SEMI }
| "&"
    { INTER }
| "->"
    { ARROW }
| "<:"
    { LPROJ }
| ":>"
    { RPROJ }
| ".."
		{ DOTDOT }
| "."
    { DOT }
| "~"
    { TILDE }
| "*"
    { STAR }
| "^"
    { HAT } 
| "="
    { EQ }
| "("
    { LPAREN }
| ")"
    { RPAREN }
| "["
    { LBRACKET }
| "]"
    { RBRACKET }
| ","
    { COMMA }
| ":"
    { COLON }
| "{"
    {  LBRACE }
| "}"
    {  RBRACE }
| "++"
    { OVERRIDE }
| "+"
    { PLUS }
| "-"
    { MINUS }
| ("=<" | "<=")
    { LTE }
| ">="
    { GTE }
| "<"
    { LT }
| ">"
    { GT }
| "|"
    { BAR }
| comment_line (* [^newline]* newline *)
    { line_comment infile lexbuf }
    (* new_line lexbuf; main tokens lexbuf } *)
(* | comment_line eof *)
(*     { tokenize EOF lexbuf :: tokens } *)
| "(*"
    { comment infile 1 lexbuf }
    (* { comment (lexeme_start_p lexbuf) tokens lexbuf; *)
    (*   main tokens lexbuf } *)
 | eof 
     { EOF } 
| _ as c
    { Msg.Fatal.lexical
@@ fun args -> args infile lexbuf ("unexpected character(s): " 
                    ^ (String.make 1 c)) }
(* and comment openingp tokens = parse *)

and line_comment infile = parse
| newline
    { new_line lexbuf; main infile lexbuf }
| eof  
     { EOF } 
| _
    { line_comment infile lexbuf }
  

and comment infile opened = parse
| "(*"
    { comment infile (opened + 1) lexbuf }
| "*)"
    { let nb = opened - 1 in
      if nb < 1 then main infile lexbuf
      else comment infile nb lexbuf }
| newline
    { new_line lexbuf; comment infile opened lexbuf }
| eof
    { Msg.Fatal.lexical
@@ fun args -> args infile lexbuf "end of file within unterminated comment" }
| _
    { comment infile opened lexbuf }


{ (* BEGIN FOOTER *)

  

} (* END FOOTER *)