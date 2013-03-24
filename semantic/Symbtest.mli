val show_offsets : bool
val pretty_dim : Format.formatter -> Types.dim -> unit
val pretty_typ : Format.formatter -> Types.typ -> unit
val pretty_mode : Format.formatter -> Types.pass_mode -> unit
val printSymbolTable : unit -> unit
val printState : string -> string -> ('a -> 'b) -> 'a -> unit
val print_solved : (Types.typ * Types.typ) list -> unit
