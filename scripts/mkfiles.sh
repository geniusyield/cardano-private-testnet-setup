#!/usr/bin/env bash

set -e
# Unofficial bash strict mode.
# See: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -u
set -o pipefail



SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
. "${SCRIPT_PATH}"/config-read.shlib; # load the config library functions


ROOT="$(config_get ROOT)";
INIT_SUPPLY=$(config_get INIT_SUPPLY);

NETWORK_MAGIC=42
SECURITY_PARAM=10
NUM_SPO_NODES=3

UNAME=$(uname -s) SED=
case $UNAME in
  Darwin )      SED="gsed";;
  Linux )       SED="sed";;
esac

sprocket() {
  if [ "$UNAME" == "Windows_NT" ]; then
    # Named pipes names on Windows must have the structure: "\\.\pipe\PipeName"
    # See https://docs.microsoft.com/en-us/windows/win32/ipc/pipe-names
    echo -n '\\.\pipe\'
    echo "$1" | sed 's|/|\\|g'
  else
    echo "$1"
  fi
}

UNAME=$(uname -s) DATE=
case $UNAME in
  Darwin )      DATE="gdate";;
  Linux )       DATE="date";;
  MINGW64_NT* ) UNAME="Windows_NT"
                DATE="date";;
esac

START_TIME="$(${DATE} -d "now + 30 seconds" +%s)"
START_TIME_UTC=$(${DATE} -d @${START_TIME} --utc +%FT%TZ)

if ! mkdir "${ROOT}"; then
  echo "The ${ROOT} directory already exists, please move or remove it"
  exit
fi

cat > "${ROOT}/byron.genesis.spec.json" <<EOF
{
  "heavyDelThd":     "300000000000",
  "maxBlockSize":    "2000000",
  "maxTxSize":       "4096",
  "maxHeaderSize":   "2000000",
  "maxProposalSize": "700",
  "mpcThd": "20000000000000",
  "scriptVersion": 0,
  "slotDuration": "1000",
  "softforkRule": {
    "initThd": "900000000000000",
    "minThd": "600000000000000",
    "thdDecrement": "50000000000000"
  },
  "txFeePolicy": {
    "multiplier": "43946000000",
    "summand": "155381000000000"
  },
  "unlockStakeEpoch": "18446744073709551615",
  "updateImplicit": "10000",
  "updateProposalThd": "100000000000000",
  "updateVoteThd": "1000000000000"
}
EOF

cardano-cli byron genesis genesis \
  --protocol-magic ${NETWORK_MAGIC} \
  --start-time "${START_TIME}" \
  --k ${SECURITY_PARAM} \
  --n-poor-addresses 0 \
  --n-delegate-addresses ${NUM_SPO_NODES} \
  --total-balance ${INIT_SUPPLY} \
  --delegate-share 1 \
  --avvm-entry-count 0 \
  --avvm-entry-balance 0 \
  --protocol-parameters-file "${ROOT}/byron.genesis.spec.json" \
  --genesis-output-dir "${ROOT}/byron-gen-command"

# Copy the cost model

cp configuration/babbage/alonzo-babbage-test-genesis.json "${ROOT}/genesis.alonzo.spec.json"
cp configuration/babbage/conway-babbage-test-genesis.json "${ROOT}/genesis.conway.spec.json"

cp configuration/defaults/byron-mainnet/configuration.yaml "${ROOT}/"
$SED -i "${ROOT}/configuration.yaml" \
     -e 's/Protocol: RealPBFT/Protocol: Cardano/' \
     -e '/Protocol/ aPBftSignatureThreshold: 0.6' \
     -e 's/minSeverity: Info/minSeverity: Debug/' \
     -e 's|GenesisFile: genesis.json|ByronGenesisFile: genesis/byron/genesis.json|' \
     -e '/ByronGenesisFile/ aShelleyGenesisFile: genesis/shelley/genesis.json' \
     -e '/ByronGenesisFile/ aAlonzoGenesisFile: genesis/shelley/genesis.alonzo.json' \
     -e '/ByronGenesisFile/ aConwayGenesisFile: genesis/shelley/genesis.conway.json' \
     -e 's/RequiresNoMagic/RequiresMagic/' \
     -e 's/LastKnownBlockVersion-Major: 0/LastKnownBlockVersion-Major: 6/' \
     -e 's/LastKnownBlockVersion-Minor: 2/LastKnownBlockVersion-Minor: 0/'

  echo "TestShelleyHardForkAtEpoch: 0" >> "${ROOT}/configuration.yaml"
  echo "TestAllegraHardForkAtEpoch: 0" >> "${ROOT}/configuration.yaml"
  echo "TestMaryHardForkAtEpoch: 0" >> "${ROOT}/configuration.yaml"
  echo "TestAlonzoHardForkAtEpoch: 0" >> "${ROOT}/configuration.yaml"
  echo "TestBabbageHardForkAtEpoch: 0" >> "${ROOT}/configuration.yaml"
  echo "TestConwayHardForkAtEpoch: 0" >> "${ROOT}/configuration.yaml"
  echo "TestEnableDevelopmentNetworkProtocols: True" >> "${ROOT}/configuration.yaml"

# Because in Babbage the overlay schedule and decentralization parameter
# are deprecated, we must use the "create-staked" cli command to create
# SPOs in the ShelleyGenesis

cardano-cli genesis create-staked --genesis-dir "${ROOT}" \
  --testnet-magic "${NETWORK_MAGIC}" \
  --start-time $START_TIME_UTC \
  --gen-pools 3 \
  --supply 1000000000000 \
  --supply-delegated 1000000000000 \
  --gen-stake-delegs 3 \
  --gen-utxo-keys 3

SPO_NODES="node-spo1 node-spo2 node-spo3"

# create the node directories
for NODE in ${SPO_NODES}; do

  mkdir "${ROOT}/${NODE}"

done

# Make topology files
#TODO generalise this over the N BFT nodes and pool nodes
cat > "${ROOT}/node-spo1/topology.json" <<EOF
{
   "Producers": [
     {
       "addr": "127.0.0.1",
       "port": 3002,
       "valency": 1
     }
   , {
       "addr": "127.0.0.1",
       "port": 3003,
       "valency": 1
     }
   ]
 }
EOF

cat > "${ROOT}/node-spo2/topology.json" <<EOF
{
   "Producers": [
     {
       "addr": "127.0.0.1",
       "port": 3001,
       "valency": 1
     }
   , {
       "addr": "127.0.0.1",
       "port": 3003,
       "valency": 1
     }
   ]
 }
EOF

cat > "${ROOT}/node-spo3/topology.json" <<EOF
{
   "Producers": [
     {
       "addr": "127.0.0.1",
       "port": 3001,
       "valency": 1
     }
   , {
       "addr": "127.0.0.1",
       "port": 3002,
       "valency": 1
     }
   ]
 }
EOF

echo 3001 > "${ROOT}/node-spo1/port"
echo 3002 > "${ROOT}/node-spo2/port"
echo 3003 > "${ROOT}/node-spo3/port"

# Move all genesis related files
mkdir -p "${ROOT}/genesis/byron"
mkdir -p "${ROOT}/genesis/shelley"

mv "${ROOT}/byron-gen-command/genesis.json" "${ROOT}/genesis/byron/genesis-wrong.json"
mv "${ROOT}/genesis.alonzo.json" "${ROOT}/genesis/shelley/genesis.alonzo.json"
mv "${ROOT}/genesis.conway.json" "${ROOT}/genesis/shelley/genesis.conway.json"
mv "${ROOT}/genesis.json" "${ROOT}/genesis/shelley/genesis.json"

jq --raw-output '.protocolConsts.protocolMagic = 42' "${ROOT}/genesis/byron/genesis-wrong.json" > "${ROOT}/genesis/byron/genesis.json"

rm "${ROOT}/genesis/byron/genesis-wrong.json"

cp "${ROOT}/genesis/shelley/genesis.json" "${ROOT}/genesis/shelley/copy-genesis.json"

jq -M '. + {slotLength:0.1, securityParam:10, activeSlotsCoeff:0.1, securityParam:10, epochLength:500, maxLovelaceSupply:1000000000000, updateQuorum:2}' "${ROOT}/genesis/shelley/copy-genesis.json" > "${ROOT}/genesis/shelley/copy2-genesis.json"
jq --raw-output '.protocolParams.protocolVersion.major = 7 | .protocolParams.minFeeA = 44 | .protocolParams.minFeeB = 155381 | .protocolParams.minUTxOValue = 1000000 | .protocolParams.decentralisationParam = 0.7 | .protocolParams.rho = 0.1 | .protocolParams.tau = 0.1' "${ROOT}/genesis/shelley/copy2-genesis.json" > "${ROOT}/genesis/shelley/genesis.json"

rm "${ROOT}/genesis/shelley/copy2-genesis.json"
rm "${ROOT}/genesis/shelley/copy-genesis.json"

mv "${ROOT}/pools/vrf1.skey" "${ROOT}/node-spo1/vrf.skey"
mv "${ROOT}/pools/vrf2.skey" "${ROOT}/node-spo2/vrf.skey"
mv "${ROOT}/pools/vrf3.skey" "${ROOT}/node-spo3/vrf.skey"

mv "${ROOT}/pools/opcert1.cert" "${ROOT}/node-spo1/opcert.cert"
mv "${ROOT}/pools/opcert2.cert" "${ROOT}/node-spo2/opcert.cert"
mv "${ROOT}/pools/opcert3.cert" "${ROOT}/node-spo3/opcert.cert"

mv "${ROOT}/pools/kes1.skey" "${ROOT}/node-spo1/kes.skey"
mv "${ROOT}/pools/kes2.skey" "${ROOT}/node-spo2/kes.skey"
mv "${ROOT}/pools/kes3.skey" "${ROOT}/node-spo3/kes.skey"

#Byron related

mv "${ROOT}/byron-gen-command/delegate-keys.000.key" "${ROOT}/node-spo1/byron-delegate.key"
mv "${ROOT}/byron-gen-command/delegate-keys.001.key" "${ROOT}/node-spo2/byron-delegate.key"
mv "${ROOT}/byron-gen-command/delegate-keys.002.key" "${ROOT}/node-spo3/byron-delegate.key"

mv "${ROOT}/byron-gen-command/delegation-cert.000.json" "${ROOT}/node-spo1/byron-delegation.cert"
mv "${ROOT}/byron-gen-command/delegation-cert.001.json" "${ROOT}/node-spo2/byron-delegation.cert"
mv "${ROOT}/byron-gen-command/delegation-cert.002.json" "${ROOT}/node-spo3/byron-delegation.cert"

# Make some payment and stake addresses
# user1..n:       will own all the funds in the system, we'll set this up from
#                 initial utxo the
# pool-owner1..n: will be the owner of the pools and we'll use their reward
#                 account for pool rewards

USER_ADDRS="user1"

ADDRS="${USER_ADDRS}"

mkdir "${ROOT}/addresses"

for ADDR in ${ADDRS}; do

  # Payment address keys
  cardano-cli address key-gen \
      --verification-key-file "${ROOT}/addresses/${ADDR}.vkey" \
      --signing-key-file      "${ROOT}/addresses/${ADDR}.skey"

  # Stake address keys
  cardano-cli stake-address key-gen \
      --verification-key-file "${ROOT}/addresses/${ADDR}-stake.vkey" \
      --signing-key-file      "${ROOT}/addresses/${ADDR}-stake.skey"

  # Payment addresses
  cardano-cli address build \
      --payment-verification-key-file "${ROOT}/addresses/${ADDR}.vkey" \
      --stake-verification-key-file "${ROOT}/addresses/${ADDR}-stake.vkey" \
      --testnet-magic ${NETWORK_MAGIC} \
      --out-file "${ROOT}/addresses/${ADDR}.addr"

  # Stake addresses
  cardano-cli stake-address build \
      --stake-verification-key-file "${ROOT}/addresses/${ADDR}-stake.vkey" \
      --testnet-magic ${NETWORK_MAGIC} \
      --out-file "${ROOT}/addresses/${ADDR}-stake.addr"

  # Stake addresses registration certs
  cardano-cli stake-address registration-certificate \
      --stake-verification-key-file "${ROOT}/addresses/${ADDR}-stake.vkey" \
      --out-file "${ROOT}/addresses/${ADDR}-stake.reg.cert"

done

echo "Generated payment address keys, stake address keys,"
echo "stake address registration certs, and stake address delegation certs"
echo
ls -1 "${ROOT}/addresses/"
echo "====================================================================="

# compute the ByronGenesisHash and add to configuration.yaml
byronGenesisHash=$(cardano-cli byron genesis print-genesis-hash --genesis-json "${ROOT}/genesis/byron/genesis.json")
echo "ByronGenesisHash: $byronGenesisHash" >> "${ROOT}/configuration.yaml"

# compute the Shelley genesis hash and add to configuration.yaml
shelleyGenesisHash=$(cardano-cli genesis hash --genesis "${ROOT}/genesis/shelley/genesis.json")
echo "ShelleyGenesisHash: $shelleyGenesisHash" >> "${ROOT}/configuration.yaml"

# compute the Shelley Alonzo genesis hash and add to configuration.yaml
alonzoGenesisHash=$(cardano-cli genesis hash --genesis "${ROOT}/genesis/shelley/genesis.alonzo.json")
echo "AlonzoGenesisHash: $alonzoGenesisHash" >> "${ROOT}/configuration.yaml"

# These are needed for cardano-submit-api
echo "EnableLogMetrics: False" >> "${ROOT}/configuration.yaml"
echo "EnableLogging: True" >> "${ROOT}/configuration.yaml"

for NODE in ${SPO_NODES}; do
  (
    echo "#!/usr/bin/env bash"
    echo ""
    echo "cardano-node run \\"
    echo "  --config                          '${ROOT}/configuration.yaml' \\"
    echo "  --topology                        '${ROOT}/${NODE}/topology.json' \\"
    echo "  --database-path                   '${ROOT}/${NODE}/db' \\"
    echo "  --socket-path                     '$(sprocket "${ROOT}/${NODE}/node.sock")' \\"
    echo "  --shelley-kes-key                 '${ROOT}/${NODE}/kes.skey' \\"
    echo "  --shelley-vrf-key                 '${ROOT}/${NODE}/vrf.skey' \\"
    echo "  --byron-delegation-certificate    '${ROOT}/${NODE}/byron-delegation.cert' \\"
    echo "  --byron-signing-key               '${ROOT}/${NODE}/byron-delegate.key' \\"
    echo "  --shelley-operational-certificate '${ROOT}/${NODE}/opcert.cert' \\"
    echo "  --port                            $(cat "${ROOT}/${NODE}/port") \\"
    echo "  | tee -a '${ROOT}/${NODE}/node.log'"
  ) > "${ROOT}/${NODE}.sh"

  chmod a+x "${ROOT}/${NODE}.sh"

  echo "${ROOT}/${NODE}.sh"
done

mkdir -p "${ROOT}/run"

echo "#!/usr/bin/env bash" > "${ROOT}/run/all.sh"
echo "" >> "${ROOT}/run/all.sh"

for NODE in ${SPO_NODES}; do
  echo "$ROOT/${NODE}.sh &" >> "${ROOT}/run/all.sh"
done
echo "" >> "${ROOT}/run/all.sh"
echo "wait" >> "${ROOT}/run/all.sh"

chmod a+x "${ROOT}/run/all.sh"

echo "CARDANO_NODE_SOCKET_PATH=${ROOT}/node-spo1/node.sock "

echo
echo "Alternatively, you can run all the nodes in one go:"
echo
echo "$ROOT/run/all.sh"
