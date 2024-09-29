#!/bin/bash -eux

# Hyperledger Fabric Chaincode Deployment Script
# Enhancements based on the latest Hyperledger Fabric release

trap "exit" INT TERM
trap "kill 0" EXIT

SRCDIR=$(realpath $(dirname $0))
ORIGDIR=$PWD
DESTDIR=$1

LOG_DIR="$DESTDIR/logs"
CHAINCODE_PATH="$SRCDIR/pkg"
CHAINCODE_NAME="mycc"
CHAINCODE_LABEL="mycc"
CHAINCODE_TYPE="ocaml"
CHAINCODE_METADATA_DIR="$DESTDIR/package"
CHAINCODE_TAR_GZ="$CHAINCODE_METADATA_DIR/${CHAINCODE_NAME}.tar.gz"
CHAINCODE_ID=""
FABRIC_CFG_PATH="$DESTDIR/fabric/sampleconfig"

# Ensure necessary directories exist
mkdir -p $DESTDIR
mkdir -p $LOG_DIR

cd $DESTDIR

# 1 -- Clone Fabric repository (latest stable)
git clone https://github.com/hyperledger/fabric --depth 1
cd fabric

# 1.5 -- Modify configuration files
sed -i sampleconfig/core.yaml sampleconfig/orderer.yaml -e "s&/var/hyperledger/production&$PWD/../tmp&g"
sed -i sampleconfig/core.yaml -e "s&127.0.0.1:9443&127.0.0.1:9447&g"
sed -i sampleconfig/core.yaml -e "s&0.0.0.0:7051&127.0.0.1:7051&g"

# 2 -- Build Fabric binaries
make orderer peer configtxgen

# 2.5 -- Create chaincode package
rm -rf $CHAINCODE_METADATA_DIR; mkdir -p $CHAINCODE_METADATA_DIR
echo "{\"path\":\"fabric-chaincode-ocaml/tests/simple\",\"type\":\"$CHAINCODE_TYPE\",\"label\":\"$CHAINCODE_LABEL\"}" > $CHAINCODE_METADATA_DIR/metadata.json

tar -czf code.tar.gz -C $CHAINCODE_PATH --exclude=_build --exclude=.git --exclude=_opam --exclude=pkg .
tar -czf $CHAINCODE_TAR_GZ code.tar.gz metadata.json

# 2.6 -- Create external launcher scripts
rm -rf $DESTDIR/bin/; mkdir -p $DESTDIR/bin/

# Detect script
cat > $DESTDIR/bin/detect <<EOF
#!/bin/sh -eux
exec 1>/tmp/detect.log 2>&1
CHAINCODE_METADATA_DIR="\$2"
if [ "\$(jq -r .type "\$CHAINCODE_METADATA_DIR/metadata.json" | tr '[:upper:]' '[:lower:]')" = "$CHAINCODE_TYPE" ]; then
    exit 0
fi
exit 1
EOF

# Build script
cat > $DESTDIR/bin/build <<EOF
#!/bin/sh -eux
exec 1>/tmp/build.log 2>&1
CHAINCODE_SOURCE_DIR="\$1"
BUILD_OUTPUT_DIR="\$3"
dune build --root=\$CHAINCODE_SOURCE_DIR
dune install --root=\$CHAINCODE_SOURCE_DIR --prefix=\$BUILD_OUTPUT_DIR --verbose
echo done
EOF

# Run script
cat > $DESTDIR/bin/run <<EOF
#!/bin/sh -eux
exec 1>/tmp/run.log 2>&1
BUILD_OUTPUT_DIR="\$1"
RUN_METADATA_DIR="\$2"
export CORE_CHAINCODE_ID_NAME="\$(jq -r .chaincode_id "\$RUN_METADATA_DIR/chaincode.json")"
export CORE_PEER_TLS_ENABLED="true"
export CORE_TLS_CLIENT_CERT_FILE="\$RUN_METADATA_DIR/client.crt"
export CORE_TLS_CLIENT_KEY_FILE="\$RUN_METADATA_DIR/client.key"
export CORE_PEER_TLS_ROOTCERT_FILE="\$RUN_METADATA_DIR/root.crt"
export CORE_PEER_LOCALMSPID="\$(jq -r .mspid "\$RUN_METADATA_DIR/chaincode.json")"
PEER_ADDRESS="\$(jq -r .peer_address "\$RUN_METADATA_DIR/chaincode.json")"
\$BUILD_OUTPUT_DIR/bin/chaincode \$PEER_ADDRESS \$CORE_CHAINCODE_ID_NAME
EOF

chmod u+x $DESTDIR/bin/*

# 3 -- Set Fabric environment variables
export CORE_CHAINCODE_EXTERNALBUILDERS="[{name: ocaml, path: \"$DESTDIR/\"}]"
export PATH=$(pwd)/build/bin:$PATH
export FABRIC_CFG_PATH=$(pwd)/sampleconfig

# 4 -- Create Genesis block
rm -rf sampleconfig/genesisblock ch1.block ch1.tx $DESTDIR/tmp
configtxgen -profile SampleDevModeSolo -channelID syschannel -outputBlock genesisblock -configPath $FABRIC_CFG_PATH

# 5 -- Start orderer
ORDERER_GENERAL_GENESISPROFILE=SampleDevModeSolo orderer >& $LOG_DIR/orderer.log &

timeout 2 tail -f $LOG_DIR/orderer.log || true

# 6 -- Start peer
FABRIC_LOGGING_SPEC=chaincode=debug CORE_PEER_CHAINCODELISTENADDRESS=127.0.0.1:7052 peer node start >& $LOG_DIR/peer.log &

timeout 5 tail -f $LOG_DIR/peer.log || true

# 7 -- Create channel ch1
configtxgen -channelID ch1 -outputCreateChannelTx ch1.tx -profile SampleSingleMSPChannel -configPath $FABRIC_CFG_PATH
peer channel create -o 127.0.0.1:7050 -c ch1 -f ch1.tx
peer channel join -b ch1.block

# 8 -- Install chaincode
peer lifecycle chaincode install $CHAINCODE_TAR_GZ |& tee $LOG_DIR/chaincode-install.log
CHAINCODE_ID=$(sed -ne "s/^.*code package identifier: $CHAINCODE_NAME:\([a-z0-9]*\).*$/\1/p" $LOG_DIR/chaincode-install.log)
test -n "$CHAINCODE_ID"

# 9 -- Approve and commit the chaincode definition
peer lifecycle chaincode approveformyorg -o 127.0.0.1:7050 --channelID ch1 --name $CHAINCODE_NAME --version 1.0 --sequence 1 --init-required --signature-policy "OR ('SampleOrg.member')" --package-id $CHAINCODE_NAME:$CHAINCODE_ID
peer lifecycle chaincode checkcommitreadiness -o 127.0.0.1:7050 --channelID ch1 --name $CHAINCODE_NAME --version 1.0 --sequence 1 --init-required --signature-policy "OR ('SampleOrg.member')"
peer lifecycle chaincode commit -o 127.0.0.1:7050 --channelID ch1 --name $CHAINCODE_NAME --version 1.0 --sequence 1 --init-required --signature-policy "OR ('SampleOrg.member')" --peerAddresses 127.0.0.1:7051

# 10 -- Invoke chaincode
CORE_PEER_ADDRESS=127.0.0.1:7051 peer chaincode invoke -o 127.0.0.1:7050 -C ch1 -n $CHAINCODE_NAME -c '{"Args":["init","a","100","b","200"]}' --isInit

cd $ORIGDIR
