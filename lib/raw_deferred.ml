open Import

module Ivar = Raw_ivar

(* Deferreds present a covariant view of ivars.  We could actually implement deferreds
   using a record of closures, as in the [essence_of_deferred] record below, for which the
   OCaml type checker can infer covariance.  However, doing so would make [Ivar.read] very
   costly, because it would have to allocate lots of closures and a record.  Instead of
   doing this, we make deferreds an abstract covariant type, which concretely is just the
   ivar, and use [Obj.magic] to convert back and forth between a deferred and its concrete
   representation as an ivar.  This [Obj.magic] is safe because the representation is
   always just an ivar, and the covariance follows from the fact that all the deferred
   operations are equivalent to those implemented directly on top of the
   [essence_of_deferred]. *)
(*
type (+'a, 'execution_context) essence_of_deferred =
  { peek : unit -> 'a option;
    is_determined : unit -> bool;
    upon : ('a -> unit) -> unit;
    upon' : ('a -> unit) -> Unregister.t;
    install_removable_handler : ('a, 'execution_context) Raw_handler.t -> Unregister.t;
  }
*)

type +'a t  (* the abstract covariant type, equivalent to ivar *)

type 'a deferred = 'a t

let of_ivar (type a) (ivar : a Ivar.t) = (Obj.magic ivar : a t)

let to_ivar (type a) (t : a t) = (Obj.magic t : a Ivar.t)

let sexp_of_t sexp_of_a t = Ivar.sexp_of_t sexp_of_a (to_ivar t)

let peek t = Ivar.peek (to_ivar t)

let return a = of_ivar (Ivar.create_full a)

let is_determined t = Ivar.is_full (to_ivar t)

let upon t f = Ivar.upon (to_ivar t) f

let upon' t f = Ivar.upon' (to_ivar t) f

let create f =
  let result = Ivar.create () in
  f result;
  of_ivar result;
;;

let bind t f =
  create (fun bind_result ->
    upon t (fun a -> Ivar.connect ~bind_result ~bind_rhs:(to_ivar (f a))))
;;

let install_removable_handler t f = Ivar.install_removable_handler (to_ivar t) f
