include (struct

module M (S : sig val add : int -> int -> int end) = struct 
  let u = S.add 1 2 
end
module H = M(struct let add x y = x +  y end)

include List 
module N = List
let v = N.length


module Make(U:Set.OrderedType) = struct
  include U
  let v = compare
end


module X = Make(String)
module U = Make(Test_order)

include N


end : sig end)