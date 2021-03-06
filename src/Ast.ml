open Format
open Identifier
open Error
open Types
open Pretty_print
open SymbTypes
open Symbol
open Typeinf
open AstTypes

exception RecDef of string
exception ConstrParamTyp of  string * string
exception ConstrParamArity of string * int * int 
exception NewArray

(* Standard Library Functions*)
let library_funs = 
  [("print_int", T_Unit, [("a", T_Int)]);
   ("print_bool", T_Unit, [("a", T_Bool)]);
   ("print_char", T_Unit, [("a", T_Char)]);
   ("print_float", T_Unit, [("a", T_Float)]);
   ("print_string", T_Unit, [("a", T_Array (T_Char, D_Dim 1))]);
   ("read_int", T_Int, [("a", T_Unit)]);
   ("read_bool", T_Bool, [("a", T_Unit)]);
   ("read_char", T_Char, [("a", T_Unit)]);
   ("read_float", T_Float, [("a", T_Unit)]);
   ("read_string", T_Unit, [("a",  T_Array (T_Char, D_Dim 1))]);
   ("abs", T_Int, [("a", T_Int)]);
   ("fabs", T_Float, [("a", T_Float)]);    
   ("sqrt", T_Float, [("a", T_Float)]);
   ("sin", T_Float, [("a", T_Float)]);
   ("cos", T_Float, [("a", T_Float)]);
   ("tan", T_Float, [("a", T_Float)]);
   ("atan", T_Float, [("a", T_Float)]);
   ("exp", T_Float, [("a", T_Float)]);
   ("ln", T_Float, [("a", T_Float)]);
   ("pi", T_Float, [("a", T_Unit)]);
   ("incr", T_Unit, [("a", T_Ref (T_Int))]);
   ("decr", T_Unit, [("a", T_Ref (T_Int))]);
   ("float_of_int", T_Float, [("a", T_Int)]);
   ("int_of_float", T_Int, [("a", T_Float)]);
   ("round", T_Int, [("a", T_Float)]);
   ("int_of_char", T_Int, [("a", T_Char)]);
   ("char_of_int", T_Char, [("a", T_Int)]);
   ("strlen", T_Int, [("a", T_Array (T_Char, D_Dim 1))]);
   ("strcmp", T_Int, 
    [("a", T_Array (T_Char, D_Dim 1)); ("b", T_Array (T_Char, D_Dim 1))]);
   ("strcpy", T_Unit,
    [("a", T_Array (T_Char, D_Dim 1)); ("b", T_Array (T_Char, D_Dim 1))]);
   ("strcat", T_Unit, 
    [("a", T_Array (T_Char, D_Dim 1)); ("b", T_Array (T_Char, D_Dim 1))])
  ]

let function_stack = Stack.create ()



let library_fun_entries = ref []

let find_lib_fun id = List.assoc id !library_fun_entries                       

let rec walk_program ls =
  initSymbolTable 10009;
  openScope();
  let f = newFunction (id_make "_outer") None true in 
  let () = endFunctionHeader f (T_Unit) in
  let () = Stack.push f function_stack in
  let () = library_fun_entries := List.map insert_function library_funs in
  let constraints = walk_stmt_list ls in
  let () = closeScope() in
  let solved = unify constraints in
    (solved, f, library_funs)

and insert_function (id, result_ty, params) =
  let p = newFunction (id_make id) (Some (Stack.top function_stack)) true in
    setLibraryFunction p;
    openScope ();
    walk_par_list params p;
    endFunctionHeader p result_ty;
    closeScope ();
    fixOffsets p;
    (id, p)

and walk_stmt_list ls = 
  let constraints = ref [] in 
  let rec walk_stmt_list_aux ls acc = match ls with
    | [] ->  constraints := acc
    | h :: t ->
      openScope ();
      let constraints1 = walk_stmt h in
        walk_stmt_list_aux t (constraints1 @ acc);
        closeScope ();
  in
    walk_stmt_list_aux ls [];
    !constraints

and walk_stmt t = match t with
  | S_Let  l -> walk_def_list l
  | S_Rec l -> 
    List.iter walk_recdef_names l;      
    let constraints = walk_recdef_list l in
      constraints
  | S_Type l -> walk_typedef_list l

and walk_def_list t = 
  let rec walk_def_list_aux t acc = match t with
    | [] -> acc
    | h :: t -> walk_def_list_aux t ((walk_def h) @ acc)
  in
    walk_def_list_aux t []

and walk_recdef_list t  = match t with
  | [] -> []
  | h :: t ->
    walk_recdef_params h;
    let constraints = walk_recdef_list t in
      (walk_recdef h) @ constraints  

and walk_def t = match t.def with
  | D_Var (l, e) ->
    begin
      match l with
        | [] -> internal "Definition cannot be empty";
        | (id, ty) :: [] ->
          let new_ty = refresh ty in
          let current_fun = Stack.top function_stack in
          let p = newVariable (id_make id) new_ty current_fun true in
          let () = hideScope !currentScope true in
          let constraints = walk_expr e in
            ignore p;
            hideScope !currentScope false;
            t.def_entry <- Some p;
            (new_ty, e.expr_typ) :: constraints
        | (id, ty) :: tl ->
          let p = 
            newFunction (id_make id) (Some (Stack.top function_stack)) true 
          in
          let () = Stack.push p function_stack in
          let () = hideScope !currentScope true in
          let () =  openScope () in
          let () = walk_par_list tl p in
          let new_ty = refresh ty in
          let () = endFunctionHeader p new_ty in
          let constraints = walk_expr e in
          let _ = Stack.pop function_stack in
            closeScope ();
            hideScope !currentScope false;
            t.def_entry <- Some p;
            (new_ty, e.expr_typ) :: (e.expr_typ, T_Nofun) :: constraints
    end
  | D_Mut (id, ty) ->     
    let new_ty = refresh ty in
    let current_fun = Stack.top function_stack in
    let p = newVariable (id_make id) (T_Ref new_ty) current_fun true in
      t.def_entry <- Some p;
      []
  | D_Array (id, ty, l) ->
    let rec walk_expr_list l acc = match l with
      | [] -> acc
      | e :: t -> 
        let constraints = walk_expr e in
          walk_expr_list t (((e.expr_typ, T_Int) :: constraints) @ acc)
    in
    let new_ty = refresh ty in
    let current_fun = Stack.top function_stack in
    let array_typ = T_Array (new_ty, D_Dim (List.length l)) in
    let p = newVariable (id_make id) array_typ current_fun true in
    let () = hideScope !currentScope true in
    let constraints = walk_expr_list l [] in
      hideScope !currentScope false;
      t.def_entry <- Some p;
      constraints

and walk_recdef_names t = match t.def with
  | D_Var (l, e) ->
    begin 
      match l with
        | [] -> internal "Definition cannot be empty";
        | (id, ty) :: []  ->
          let new_ty = refresh ty in
          let current_fun = Stack.top function_stack in
          let p = newVariable (id_make id) new_ty current_fun true in
            ignore p;
        | (id, ty) :: tl  -> 
          let new_ty = refresh ty in
          let p = 
            newFunction (id_make id) (Some (Stack.top function_stack)) true 
          in
            setType p new_ty;
            forwardFunction p
    end
  | D_Mut (id, t) -> raise (RecDef "Mutable")
  | D_Array (id, t, l) -> raise (RecDef "Array")

and walk_recdef_params t = match t.def with
  | D_Var(l, e) ->
    begin 
      match l with
        | [] -> internal "Definition cannot be empty"; 
        | (id, ty) :: [] -> ()
        | (id, ty) :: tl -> 
          let p = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
          let new_ty = getResType p in
            openScope ();
            walk_par_list tl p;
            hideScope !currentScope true;
            endFunctionHeader p new_ty;
    end
  | D_Mut (id, t) -> raise (RecDef "Mutable")
  | D_Array (id, t, l)  -> raise (RecDef "Array")  

and walk_recdef t = match t.def with
  | D_Var (l, e) ->
    begin 
      match l with
        | [] -> internal "Definition cannot be empty\n";
        | (id, ty) :: [] -> 
          hideScope !currentScope true;
          let constraints = walk_expr e in 
          let () = hideScope !currentScope false in
          let p = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
          let new_ty = getResType p in
            t.def_entry <- Some p;
            (new_ty, e.expr_typ) :: constraints
        | (id, ty) :: tl -> 
          let p = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
          let () = Stack.push p function_stack in
          let new_ty = getResType p in
          let () = hideScope !currentScope false in
          let () = e.expr_tail <- true in
          let constraints = walk_expr e in
          let _ = Stack.pop function_stack in
            closeScope ();
            t.def_entry <- Some p; 
            (new_ty, e.expr_typ) :: (e.expr_typ, T_Nofun) :: constraints
    end
  | D_Mut (id, t) -> raise (RecDef "Mutable")
  | D_Array (id, t, l)  -> raise (RecDef "Array")  

and walk_par_list l p = match l with
  | [] -> ()
  | (hid, ht) :: tl -> 
    let new_ty = refresh ht in
    let f = newParameter (id_make hid) new_ty PASS_BY_VALUE p true in
      begin
        ignore f;
        walk_par_list tl p
      end

(* Walks user defined types and initially registers the types' names into the
 * symbol table (used for mutually recursive defined types). Afterwards it
 * walks the constructors list and if they are well defined proceeds with
 * registering them as well. *)

and walk_typedef_list l = match l with
  | [] -> internal "Type definition cannot be empty"
  | l -> 
    (* Adds user defined types names to symbol table *)
    List.iter (fun (id, _) -> ignore (newUdt (id_make id) true)) l; 
    let walk_constructor tid cid types_list tag = 
      List.iter (function 
          | T_Id id -> 
            let entry = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
              begin
                match entry.entry_info with
                  | ENTRY_udt _ -> ()
                  | _ -> 
                    raise (ConstrParamTyp (cid, id)) 
              end
          | _ -> ()) types_list;
      let c = newConstructor (id_make cid) (T_Id tid) types_list tag true in
        ignore c;
    in
      List.iter (fun (id, constructors_list) -> 
          List.iteri (fun i (cid, types_list) -> 
              walk_constructor id cid types_list i) 
            constructors_list) l;
      [] (* Check return *)

and walk_expr expr_node = match expr_node.expr with
  | E_Binop (expr1, op, expr2) -> 
    begin 
      match op with 
        | Plus | Minus | Times | Div | Mod -> 
          let constraints1 = walk_expr expr1 in
          let constraints2 = walk_expr expr2 in
            expr_node.expr_typ <- T_Int;
            (expr1.expr_typ, T_Int) :: (expr2.expr_typ, T_Int) 
            :: constraints1 @ constraints2
        | Fplus | Fminus | Ftimes | Fdiv | Power -> 
          let constraints1 = walk_expr expr1 in
          let constraints2 = walk_expr expr2 in
            expr_node.expr_typ <- T_Float; 
            (expr1.expr_typ, T_Float) :: (expr2.expr_typ, T_Float) 
            :: constraints1 @ constraints2
        | Seq | Nseq | Eq | Neq -> 
          let constraints1 = walk_expr expr1 in
          let constraints2 = walk_expr expr2 in
            expr_node.expr_typ <- T_Bool; 
            (expr1.expr_typ, expr2.expr_typ) :: (expr1.expr_typ, T_Nofun)
            :: (expr1.expr_typ, T_Noarr)
            :: constraints1 @ constraints2 (* TODO Must not be array DONE*)
        | L | Le | G  | Ge -> 
          let constraints1 = walk_expr expr1 in
          let constraints2 = walk_expr expr2 in
            expr_node.expr_typ <- T_Bool; 
            (expr1.expr_typ, T_Ord) :: (expr1.expr_typ, expr2.expr_typ) 
            :: constraints1 @ constraints2 
        | And | Or -> 
          let constraints1 = walk_expr expr1 in
          let constraints2 = walk_expr expr2 in
            expr_node.expr_typ <- T_Bool; 
            (expr1.expr_typ, T_Bool) :: (expr2.expr_typ, T_Bool) 
            :: constraints1 @ constraints2
        | Semicolon -> 
          let constraints1 = walk_expr expr1 in
          let () = expr2.expr_tail <- expr_node.expr_tail in
          let constraints2 = walk_expr expr2 in
            expr_node.expr_typ <- expr2.expr_typ;
            constraints1 @ constraints2
        | Assign -> 
          let constraints1 = walk_expr expr1 in
          let constraints2 = walk_expr expr2 in     
            expr_node.expr_typ <- T_Unit;   
            (T_Ref expr2.expr_typ, expr1.expr_typ) 
            :: constraints1 @ constraints2
    end
  | E_Unop (op, expr1) ->
    begin
      match op with
        | U_Plus | U_Minus -> 
          let constraints1 = walk_expr expr1 in 
            expr_node.expr_typ <- T_Int;
            (expr1.expr_typ, T_Int) :: constraints1
        | U_Fplus | U_Fminus -> 
          let constraints1 = walk_expr expr1 in 
            expr_node.expr_typ <- T_Float;
            (expr1.expr_typ, T_Float) :: constraints1
        | U_Del -> 
          let constraints1 = walk_expr expr1 in
            expr_node.expr_typ <- T_Unit;
            (expr1.expr_typ, T_Ref fresh()) :: constraints1
        | U_Not -> 
          let constraints1 = walk_expr expr1 in
            expr_node.expr_typ <- T_Bool;
            (expr1.expr_typ, T_Bool) :: constraints1
    end
  | E_Block expr1 -> 
    let () = expr1.expr_tail <- expr_node.expr_tail in 
    let constraints = walk_expr expr1 in
      expr_node.expr_typ <- expr1.expr_typ;
      constraints  
  | E_While (expr1, expr2) -> 
    let constraints1 = walk_expr expr1 in
    let constraints2 = walk_expr expr2 in  
      expr_node.expr_typ <- T_Unit;
      (expr1.expr_typ, T_Bool) :: (expr2.expr_typ, T_Unit) 
      :: constraints1 @ constraints2
  | E_For (id, expr1, cnt, expr2, expr3) ->
    openScope();
    let current_fun = Stack.top function_stack in
    let i = newVariable (id_make id) T_Int current_fun true in
      ignore i;
      let constraints1 = walk_expr expr1 in
      let constraints2 = walk_expr expr2 in 
      let constraints3 = walk_expr expr3 in
        closeScope();
        expr_node.expr_entry <- Some i;
        expr_node.expr_typ <- T_Unit;
        ( (expr1.expr_typ, T_Int) :: (expr2.expr_typ, T_Int) 
          :: (expr3.expr_typ, T_Unit) :: constraints1 
          @ constraints2 @ constraints3 )
  | E_Dim (mbi, id) -> (* XXX Consider check whether a >= (dims a) *)
    let i = match mbi with
      | Some i -> i
      | None -> 1 
    in
    let id_entry = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in         
    let typ = getType id_entry in
      expr_node.expr_typ <- T_Int;
      expr_node.expr_entry <- Some id_entry;
      let dims = freshDim () in
        dimsGeq dims i;
        [(typ, T_Array (fresh (), dims))]
  | E_Ifthenelse (expr1, expr2, expr3) ->
    let constraints1 = walk_expr expr1 in
    let () = expr2.expr_tail <- expr_node.expr_tail in 
    let constraints2 = walk_expr expr2 in 
    let () = expr3.expr_tail <- expr_node.expr_tail in 
    let constraints3 = walk_expr expr3 in
      expr_node.expr_typ <- expr2.expr_typ;
      (expr1.expr_typ, T_Bool) :: (expr2.expr_typ, expr3.expr_typ) 
      :: constraints1 @ constraints2 @ constraints3
  | E_Ifthen (expr1, expr2) -> 
    let constraints1 = walk_expr expr1 in
    let () = expr2.expr_tail <- expr_node.expr_tail in 
    let constraints2 = walk_expr expr2 in 
      expr_node.expr_typ <- T_Unit;
      (expr1.expr_typ, T_Bool) :: (expr2.expr_typ, T_Unit) 
      :: constraints1 @ constraints2
  | E_Id (id, l) ->  (* function application *)
    let id_entry = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
    let fun_typ = getType id_entry in
    let res_typ = fresh () in
    (* walk parameters construct function type and generate constraints *)
    let rec walk_params params = match params with 
      | [] -> (res_typ, [])
      | x :: xs -> 
        let constraints1 = walk_atom x in
        let (typ, constraints2) = walk_params xs in
          (T_Arrow (x.atom_typ, typ), constraints1 @ constraints2)
    in
    let (typ, constraints) = walk_params l in
      expr_node.expr_typ <- res_typ;
      expr_node.expr_entry <- Some id_entry;
      ((res_typ, T_Nofun) :: (typ, fun_typ) :: constraints)
  | E_Cid (id, l) -> 
    let cid_entry = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
      begin
        match cid_entry.entry_info with
          | ENTRY_constructor constructor_info ->
            let constraints = 
              try ( List.fold_left2 (fun acc atom typ ->
                  let atom_constr = walk_atom atom in
                    (atom.atom_typ, typ) :: atom_constr @ acc )
                  [] l (constructor_info.constructor_paramlist)) 
              with Invalid_argument _ ->
                raise (ConstrParamArity 
                         (id, 
                          (List.length constructor_info.constructor_paramlist), 
                          (List.length l))
                      )
            in
              expr_node.expr_typ <- constructor_info.constructor_type;
              expr_node.expr_entry <- Some cid_entry;
              constraints
          | _ -> 
            internal "Kaname malakia soz. expected constructor gia na ksereis"
      end
  | E_Match (expr1, l) -> 
    begin 
      let constraints1 = walk_expr expr1 in
      let () = 
        List.iter (fun (Clause (_, e)) -> e.expr_tail <- expr_node.expr_tail) l
      in
      let (result_typ, pat_typ, result_constraints) = walk_clause_list l in
        expr_node.expr_typ <- result_typ;
        (expr1.expr_typ, pat_typ) :: constraints1 @ result_constraints
    end
  | E_New ty1 ->
    begin
      match ty1 with
        | T_Array _ -> raise NewArray
        | ty1 -> 
          expr_node.expr_typ <- T_Ref ty1;
          []
    end
  | E_Letin (l, expr) -> 
    openScope();
    let constraints1 = walk_stmt l in
    let () = expr.expr_tail <- expr_node.expr_tail in 
    let constraints2 = walk_expr expr in
      expr_node.expr_typ <- expr.expr_typ;
      closeScope();
      constraints1 @ constraints2       
  | E_Atom a ->
    let () = a.atom_tail <- expr_node.expr_tail in
    let constraints = walk_atom a in
      expr_node.expr_typ <- a.atom_typ;
      expr_node.expr_entry <- a.atom_entry;
      constraints
  | E_None -> internal "Dummy expression, must have been removed"

and walk_atom t = match t.atom with 
  | A_Num n -> t.atom_typ <- T_Int; []
  | A_Dec f -> t.atom_typ <- T_Float; []
  | A_Chr c -> t.atom_typ <- T_Char;  []
  | A_Str str -> t.atom_typ <- T_Array(T_Char, D_Dim 1); []
  | A_Bool b -> t.atom_typ <- T_Bool; []
  | A_Cid cid -> 
    let cid_entry = lookupEntry (id_make cid) LOOKUP_ALL_SCOPES true in
      begin
        match cid_entry.entry_info with
          | ENTRY_constructor c_info when c_info.constructor_paramlist = [] -> 
            t.atom_typ <- c_info.constructor_type; 
            t.atom_entry <- Some cid_entry;
            []
          | ENTRY_constructor c_info ->
            raise (ConstrParamArity 
                     (cid, List.length c_info.constructor_paramlist, 0))
          | _ -> internal "internal error"
      end
  | A_Var v -> 
    begin
      let id_entry = lookupEntry (id_make v) LOOKUP_ALL_SCOPES true in 
      let id_typ = getType id_entry in
        t.atom_typ <- id_typ;
        t.atom_entry <- Some id_entry;
        []
    end
  | A_Par -> t.atom_typ <- T_Unit; [] 
  | A_Bang atom -> 
    begin 
      let constraints = walk_atom atom in
        t.atom_typ <- refresh t.atom_typ;
        (T_Ref t.atom_typ, atom.atom_typ) :: constraints
    end
  | A_Array (id, expr_list) -> 
    let rec walk_array_expr expr_list acc =
      match expr_list with
        | [] -> acc
        | (expr :: xs) ->
          let constraints = walk_expr expr in 
            walk_array_expr xs ((expr.expr_typ, T_Int) :: constraints @ acc)
    in
    let array_entry = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
    let typ_arr = getType array_entry in
    let typ = fresh() in
      t.atom_typ <- T_Ref typ;
      t.atom_entry <- Some array_entry;
      walk_array_expr expr_list 
        [(typ_arr, T_Array (typ, D_Dim (List.length expr_list)))]
  | A_Expr expr -> 
    let () = expr.expr_tail <- t.atom_tail in
    let constraints = walk_expr expr in
      t.atom_typ <- expr.expr_typ;
      constraints
  | A_None -> internal "Dummy atom, must have been removed"


(*acc = [(tp1,te1,constr1),(tp2,te2,constr2),(tp3,te3,constr3)...]
 * (tp1,te) :: [(tp1,tp2),(tp2,tp3),(tp3,...),(te1,te2),(te2,te3),(te3,..)]
 * @constr1@constr2...@constre
*)

(* Returns ( result_type , pattern_type, constraints)*)
and walk_clause_list lst =    
  let rec walk_clause_aux l prev_clause acc =
    let (prev_pat_typ, prev_expr_typ, prev_constr) = prev_clause in
      match l with
        | [] -> (prev_expr_typ, prev_pat_typ , prev_constr @ acc)  
        | h :: t -> 
          let (pat_typ, expr_typ, constr) = walk_clause h in
            walk_clause_aux t (pat_typ, expr_typ, constr) 
              ((pat_typ, prev_pat_typ) :: (expr_typ, prev_expr_typ) 
               :: acc @ prev_constr) 
  in
    match lst with 
      | [] -> internal "Clause list cannot be empty"
      | h :: t -> walk_clause_aux t (walk_clause h) []

and walk_clause t = match t with 
  | Clause(pat, expr)         -> 
    openScope(); (* should consider opening only when needed *)
    let pat_constraints = walk_pattern pat in
    let expr_constraints = walk_expr expr in 
      closeScope();
      (pat.pattern_typ, expr.expr_typ, expr_constraints @ pat_constraints)

and walk_pattern p = match p.pattern with
  | Pa_Atom a -> 
    let constraints = walk_pattom a in
      p.pattern_typ <- a.pattom_typ;
      constraints
  | Pa_Cid (cid, l) ->  
    let cid_entry = lookupEntry (id_make cid) LOOKUP_ALL_SCOPES true in
      match cid_entry.entry_info with
        | ENTRY_constructor constructor_info -> 
          let constraints = 
            try ( List.fold_left2 (fun acc pattom typ -> 
                let pattom_constraints = walk_pattom pattom in
                  (pattom.pattom_typ, typ) :: pattom_constraints @ acc ) 
                [] l constructor_info.constructor_paramlist )
            with Invalid_argument _ -> 
              raise (ConstrParamArity 
                       (cid,
                        (List.length constructor_info.constructor_paramlist),
                        (List.length l))
                    )
          in
            p.pattern_typ <- constructor_info.constructor_type;
            p.pattern_entry <- Some cid_entry;
            constraints
        | _ -> internal "we failed you again and again"

and walk_pattom t = match t.pattom with
  | P_Sign(op, num) ->
    begin
      match op with 
        | P_Plus -> t.pattom_typ <- T_Int; []
        | P_Minus -> t.pattom_typ <- T_Int; []
    end
  | P_Fsign(op, num) ->
    begin
      match op with 
        | P_Fplus -> t.pattom_typ <- T_Float; []
        | P_Fminus -> t.pattom_typ <- T_Float; []
    end
  | P_Num n -> t.pattom_typ <- T_Int;   []
  | P_Float f -> t.pattom_typ <- T_Float; []
  | P_Chr c -> t.pattom_typ <- T_Char;  []
  | P_Bool b -> t.pattom_typ <- T_Bool;  []
  | P_Id id -> 
    let new_ty = fresh() in
    let current_fun = Stack.top function_stack in 
    let id_entry = newVariable (id_make id) new_ty current_fun true in
      ignore id_entry;
      t.pattom_typ <- new_ty;
      t.pattom_entry <- Some id_entry;
      []
  | P_Cid cid -> 
    let cid_entry = lookupEntry (id_make cid) LOOKUP_ALL_SCOPES true in
      begin
        match cid_entry.entry_info with
          | ENTRY_constructor c_info when c_info.constructor_paramlist = [] -> 
            t.pattom_typ <- c_info.constructor_type;
            t.pattom_entry <- Some cid_entry;
            []
          | ENTRY_constructor c_info ->
            raise (ConstrParamArity 
                     (cid, (List.length c_info.constructor_paramlist), 0))
          | _ -> internal "we failed you again"
      end
  | P_Pattern p -> 
    let constraints = walk_pattern p in
      t.pattom_typ <- p.pattern_typ;
      constraints
