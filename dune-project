(generate_opam_files true)

(authors "François Bobot")
(maintainers "François Bobot")
(source (github bobot/fabric-chaincode-ocaml))

(package
 (name fabric-chaincode-shim)
 (depends ocaml-protoc-plugin
          ppx_deriving
          conf-protoc
          grpc
          grpc-protoc-plugin)
 (synopsis "Shim for implementing Hyperledger Fabric chaincode in OCaml")
)

(package
 (name grpc)
 (depends ctypes
          memcpy
          dune-configurator
          conf-pkg-config)
 (synopsis "Binding to libgrpc core")
)

(package
 (name grpc-protoc-plugin)
 (depends ctypes
          grpc
          ocaml-protoc-plugin)
 (synopsis "GRPC services using ocaml-protoc-plugin definitions")
)
