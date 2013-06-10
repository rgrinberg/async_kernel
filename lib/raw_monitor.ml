open Core.Std

let debug = Debug.monitor

type t =
  { name : Info.t;
    here : Source_code_position.t option;
    id : int;
    parent : t option;
    mutable error_handlers : (exn -> unit) list;
    mutable has_seen_error : bool;
    mutable someone_is_listening : bool;
    mutable kill_index : Kill_index.t;
  }
with fields

module Pretty = struct
  type one =
    { name : Info.t;
      here : Source_code_position.t option;
      id : int;
      has_seen_error : bool;
      someone_is_listening : bool;
      kill_index : Kill_index.t;
    }
  with sexp_of

  type t = one list
  with sexp_of
end

let to_pretty =
  let rec loop
      { name; here; id; parent; error_handlers = _; has_seen_error; someone_is_listening;
        kill_index;
      }
      ac =
    let ac =
      { Pretty. name; here; id; has_seen_error; someone_is_listening; kill_index } :: ac
    in
    match parent with
    | None -> List.rev ac
    | Some t -> loop t ac
  in
  fun t -> loop t [];
;;

let sexp_of_t t = Pretty.sexp_of_t (to_pretty t)

let next_id =
  let r = ref 0 in
  fun () -> incr r; !r
;;

let create_with_parent ?here ?info ?name parent =
  let id = next_id () in
  let name =
    match info, name with
    | Some i, None   -> i
    | Some i, Some s -> Info.tag i s
    | None  , Some s -> Info.of_string s
    | None  , None   -> Info.create "id" id <:sexp_of< int >>
  in
  let t =
    { name; here; parent;
      id;
      error_handlers = [];
      has_seen_error = false;
      someone_is_listening = false;
      kill_index = Kill_index.initial;
    }
  in
  if debug then Debug.log "created monitor" t <:sexp_of< t >>;
  t
;;

let main = create_with_parent ~name:"main" None

exception Shutdown

(* [update_kill_index t ~global_kill_index] finds the nearest ancestor of [t] (possibly
   [t] itself) whose kill index is up to date, i.e. is either [dead] or
   [global_kill_index].  It then sets the kill index of each monitor on the path from [t]
   to that ancestor's kill index. *)
let update_kill_index =
  let rec determine_kill_index t ~global_kill_index =
    if   Kill_index.equal t.kill_index Kill_index.dead
      || Kill_index.equal t.kill_index global_kill_index
    then t.kill_index
    else
      match t.parent with
      | None -> global_kill_index
      | Some t -> determine_kill_index t ~global_kill_index
  in
  let rec set_kill_index t ~kill_index =
    if not (Kill_index.equal t.kill_index kill_index) then begin
      t.kill_index <- kill_index;
      match t.parent with
      | None -> ()
      | Some t -> set_kill_index t ~kill_index
    end
  in
  fun t ~global_kill_index ->
    let kill_index = determine_kill_index t ~global_kill_index in
    set_kill_index t ~kill_index;
;;
