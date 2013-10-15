open Error
open Pretty_print

(* Argument parsing *)

type config = {
  mutable in_file : string option;
  mutable quads   : bool;
  mutable opt     : bool;
  mutable cfg     : bool
}

type files = {
  cin    : Pervasives.in_channel;
  cout   : Pervasives.out_channel;
  cgraph : Pervasives.out_channel
}

(* Default configuration is
 * read from stdin
 * emit assembly
 * no optimisations *)
let default_config = {
  in_file = None;
  quads = false;
  opt = false;
  cfg = false
} 


let open_files () =
  let out_ext = match default_config.quads with
    | true -> ".qua"
    | false -> ".asm"
  in
    match default_config.in_file with
      | Some name ->
        let files =
          try
            let chopped = Filename.chop_extension name in
              { cin = open_in name;
                cout = open_out (chopped ^ out_ext);
                cgraph = open_out_bin (chopped ^ ".dot")
              }
          with
            | Invalid_argument _ ->
              error "Wrong file name. Extension must be .lla";
              exit 1
            | Sys_error _ ->
              error "The file could not be opened.";
              exit 1
        in
          files
      | None ->
          { cin = stdin; 
            cout = open_out ("a" ^ out_ext);
            cgraph = open_out_bin "a.dot"
          }


let read_args () =
  let speclist =
    [("-i", Arg.Unit (fun () -> default_config.quads <- true), 
      "Emit intermediate code");
     ("-O", Arg.Unit (fun () -> default_config.opt <- true),
      "Perform optimizations");
     ("-g", Arg.Unit (fun () -> default_config.cfg <- true),
      "Output a cfg in .dot format")]
  in
  let usage = "usage: " ^ Sys.argv.(0) ^ " [-i] [-o] [-g] [infile]" in
    Arg.parse speclist (fun s -> default_config.in_file <- Some s) usage

let main =
  let () = read_args () in
  let files = open_files () in
  let lexbuf = Lexing.from_channel files.cin in
    try
      let ast = Parser.program Lexer.lexer lexbuf in
      let (solved, outer_entry, library_funs) = Ast.walk_program ast in
      let ir = Intermediate.gen_program ast solved outer_entry in
      let ir =  match default_config.cfg, default_config.opt with
        | true, true ->
            let cfg = Cfg.CFG.create_cfg ir in
              (* optimize here*)
            let () = Cfg.Dot.output_graph files.cgraph cfg in
              Printf.printf " I WORKED\n\n\n\n\n";
              Cfg.CFG.quads_of_cfg cfg
        | true, false -> 
            let cfg = Cfg.CFG.create_cfg ir in
              (* optimize here*)
            let () = Cfg.Dot.output_graph files.cgraph cfg in
              ir
        | false, true ->
            (* optimizations go here *)
            ir
        | false, false -> ir
      in 
      let () =  match default_config.quads with
        | true -> 
          Quads.printQuads (Format.formatter_of_out_channel files.cout) ir
        | false -> 
          let final = CodeGen.codeGen ir outer_entry in
          let asm = EmitMasm.emit final library_funs in
            Printf.fprintf files.cout "%s" asm;
      in
        exit 0
    with 
      | Parsing.Parse_error ->
        Printf.eprintf "Line %d: syntax error\n"
          (lexbuf.Lexing.lex_curr_p.Lexing.pos_lnum);
        exit 1
      | Typeinf.UnifyError (typ1, typ2) ->
        error "Cannot match type %a with type %a" 
          pretty_typ typ1 pretty_typ typ2;
        exit 2
      | Typeinf.TypeError (err, typ) ->
        error "Type error on type %a:\n %s" pretty_typ typ err;
        exit 2
      | Typeinf.DimError (dim1, dim2) ->
        error "Array dimensions error. Cannot match dimension size %a with %a" 
          pretty_dim dim1 pretty_dim dim2; 
        exit 2
      | Intermediate.InvalidCompare typ ->
        error "Cannot compare values of type %a" pretty_typ typ;
        exit 2

