{

exception Eof

type token =
  | ANDDEF
  | ARRAY
  | EOF
  | BEGIN
  | BOOL
  | CHAR
  | DELETE
  | DIM
  | DO
  | DONE
  | DOWNTO
  | EOL
  | ELSE
  | END
  | FALSE
  | FLOAT
  | FOR
  | IF
  | IN
  | INT
  | LET
  | MATCH
  | MOD
  | MUTABLE
  | NEW
  | NOT
  | OF
  | REC
  | REF
  | THEN
  | TO
  | TRUE
  | TYPE
  | UNIT
  | WHILE
  | WITH
  | ID 
  | CID 
  | OP 
  | GIVES
  | SEQ 
  | PLUS 
  | MINUS
  | STRING
  | TIMES
  | DIV
  | FPLUS
  | FMINUS
  | FTIMES
  | FDIV
  | POWER
  | BANK
  | SEMICOLON
  | AND
  | OR
  | NSEQ
  | L
  | G
  | LE
  | GE
  | EQ
  | NEQ
  | ASSIGN
  | LPAR
  | RPAR
  | LBRACK
  | RBRACK
  | COMA
  | COLON


let incr_linenum lexbuf =
  let pos = lexbuf.Lexing.lex_curr_p in
    lexbuf.Lexing.lex_curr_p <- { pos with
      Lexing.pos_lnum = pos.Lexing.pos_lnum + 1;
      Lexing.pos_bol = pos.Lexing.pos_cnum;
    } 

let print_error lexbuf chr = 
  let pos = lexbuf.Lexing.lex_curr_p in
  Printf.printf "line:%d-character:%d:->error::Invalid character '%c' (ascii: %d)\n" 
    (pos.Lexing.pos_lnum) (pos.Lexing.pos_cnum - pos.Lexing.pos_bol) (chr) (Char.code chr)
}

let digit = ['0'-'9']
let hexdig = ['0'-'9''a'-'f''A'-'F']
let upCase = ['A'-'Z']
let lowCase = ['a'-'z']
let id = ( upCase | lowCase | '_' | digit )
let white = ['\t' ' ']
let constChar = ( [^ '\\' '\"' '\''] ) | ( '\\'( ( ['n' 't' 'r' '0' '\\' '\'' '\"'] ) | ( 'x' hexdig hexdig ) ) )


rule token = parse
  | white  { token lexbuf }
  | ['\n'] { incr_linenum lexbuf; token lexbuf  (*; EOL*) }
  | digit+ { INT } 
  | digit+( '.'digit+('e'['-''+']?digit+)? ) { FLOAT }
  | "and" { ANDDEF }
  | "array" { ARRAY }
  | "begin"{ BEGIN } 
  | "bool" { BOOL }
  | "char" { CHAR }
  | "delete" { DELETE }
  | "dim" { DIM }
  | "do" { DO }
  | "done" { DONE }
  | "downto" { DOWNTO }
  | "else" { ELSE }
  | "end" { END }
  | "false"{ FALSE }
  | "float"{ FLOAT }
  | "for"{ FOR }
  | "if" { IF }
  | "in" { IN }
  | "int" { INT }
  | "let" { LET }
  | "match" { MATCH }
  | "mod" { MOD }
  | "mutable" { MUTABLE }
  | "new" { NEW }
  | "not" { NOT }
  | "of" { OF }
  | "rec" { REC }
  | "ref" { REF }
  | "then" { THEN }
  | "to" { TO }
  | "true" { TRUE }
  | "type" { TYPE }
  | "unit" { UNIT }
  | "while" { WHILE }
  | "with" { WITH }
  | "->" { GIVES }
  | "=" { SEQ }
  | "|" { MATCH }
  | "+" { PLUS }
  | "-" { MINUS }
  | "*" { TIMES }
  | "/" { DIV }
  | "+." { FPLUS }
  | "-." { FMINUS }
  | "*." { FTIMES }
  | "/." { FDIV }
  | "**" { POWER }
  | "!" { BANK }
  | ";" { SEMICOLON }
  | "&&" { AND }
  | "||" { OR }
  | "<>" { NSEQ }
  | "<" { L }
  | ">" { G }
  | "<=" { LE }
  | ">=" { GE }
  | "==" { EQ }
  | "!=" { NEQ }
  | ":=" { ASSIGN }
  | "(" { LPAR }
  | ")" { RPAR }
  | "[" { LBRACK }
  | "]" { RBRACK }
  | "," { COMA }
  | ":" { COLON }
  | lowCase+id* { ID }
  | upCase+id* { CID }
  | '\''constChar '\'' { CHAR }
  | '\"'[^'\n']* '\"' { STRING }
  | "--"[^'\n']* { token lexbuf }
  | "(*" { print_endline "comments start"; comments 0 lexbuf }
  | _ as chr { print_error lexbuf chr ; token lexbuf}
  | eof { print_endline "file over"; EOF }

and comments level = parse
  | "*)" { Printf.printf "comments (%d) end\n" level;
	   if level = 0 then token lexbuf
	   else comments (level-1) lexbuf
	 }
  | "(*" { Printf.printf "comments (%d) start\n" (level+1);
	  comments (level+1) lexbuf
	 }
  | '\n' { incr_linenum lexbuf ; comments level lexbuf }

  | _ { comments level lexbuf  }
  | eof { print_endline "comments not closed";
	  raise Eof
	}
{

  let string_of_token token =
    match token with
  | ANDDEF -> "ANDDEF"
  | ARRAY -> "ARRAY"
  | BEGIN -> "BEGIN"
  | BOOL -> "BOOL"
  | DELETE -> "DELETE"
  | DIM -> "DIM"
  | DO -> "DO"
  | DONE -> "DONE"
  | DOWNTO -> "DOWNTO"
  | STRING -> "STRING"
  | ELSE -> "ELSE"
  | END -> "END"
  | FALSE -> "FALSE"
  | FOR -> "FOR"
  | IF -> "IF"
  | IN -> "IN"
  | LET -> "LET"
  | MOD -> "MOD"
  | MUTABLE -> "MUTABLE"
  | NEW -> "NEW"
  | NOT -> "NOT"
  | OF -> "OF"
  | REC -> "REC"
  | REF -> "REF"
  | THEN -> "THEN"
  | TO -> "TO"
  | TRUE -> "TRUE"
  | TYPE -> "TYPE"
  | UNIT -> "UNIT"
  | WHILE -> "WHILE"
  | WITH -> "WITH"
  | ID  -> "ID"
  | CID  -> "CID"
  | OP  -> "OP"
  | INT -> "INT"
  | FLOAT -> "FLOAT"
  | CHAR -> "CHAR"
  | GIVES -> "GIVES"
  | SEQ  -> "SEQ"
  | MATCH  ->"MATCH"
  | PLUS  -> "PLUS"
  | MINUS -> "MINUS"
  | TIMES -> "TIMES"
  | DIV -> "DIV"
  | FPLUS -> "FPLUS"
  | FMINUS -> "FMINUS"
  | FTIMES -> "FTIMES"
  | FDIV -> "FDIV"
  | POWER -> "POWER"
  | EOL -> "EOL"
  | BANK -> "BANK"
  | SEMICOLON -> "SEMICOLON"
  | AND -> "AND"
  | OR -> "OR"
  | NSEQ -> "NSEQ"
  | L -> "L"
  | G -> "G"
  | LE -> "LE"
  | GE -> "GE"
  | EQ -> "EQ"
  | NEQ -> "NEQ"
  | ASSIGN -> "ASSIGN"
  | LPAR -> "LPAR"
  | RPAR -> "RPAR"
  | LBRACK -> "LBRACK"
  | RBRACK -> "RBRACK"
  | COMA -> "COMA"
  | COLON -> "COLON"
  | EOF -> "EOF"


let incr_linenum lexbuf =
  let pos = lexbuf.Lexing.lex_curr_p in
    lexbuf.Lexing.lex_curr_p <- { pos with
      Lexing.pos_lnum = pos.Lexing.pos_lnum + 1;
      Lexing.pos_bol = pos.Lexing.pos_cnum;
    }

let main =
  let cin =
    if Array.length Sys.argv >1
    then open_in Sys.argv.(1)
    else stdin
  in
  let lexbuf = Lexing.from_channel cin in
  let rec loop () =
    let token = token lexbuf in
    Printf.printf "line=%d, token=%s, lexeme=\"%s\"\n"
      ( lexbuf.Lexing.lex_curr_p.Lexing.pos_lnum)(string_of_token token) (Lexing.lexeme lexbuf);
    if token <> EOF then loop () in
  loop ()
}

