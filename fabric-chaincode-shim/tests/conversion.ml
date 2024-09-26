let () =
  (* Create a timestamp with 42 seconds *)
  let timestamp = FabricChaincodeShim.Protobuf.Timestamp.make ~seconds:42 () in
  Printf.printf "Original seconds: %i\n" timestamp.seconds;

  (* Encode the timestamp to protobuf format *)
  let encoded =
    FabricChaincodeShim.Protobuf.Timestamp.to_proto timestamp
    |> Ocaml_protoc_plugin.Writer.contents
  in
  Printf.printf "Encoded timestamp: %S\n" encoded;

  (* Decode the protobuf back to a timestamp *)
  let decoded =
    Ocaml_protoc_plugin.Reader.create encoded
    |> FabricChaincodeShim.Protobuf.Timestamp.from_proto
    |> Result.get_ok
  in
  Printf.printf "Decoded seconds: %i\n" decoded.seconds
