network=$1

deploy_local() {
  echo "Deploying local..."

  dfx identity use icpi-local

  dfx deploy --no-wallet --with-cycles=20000000000000 token_icpi --argument="(record { initial_mints = vec { record { account = record { owner = principal \"\"; subaccount = null; }; amount = 100000000000000000; }; }; minting_account =  record {owner = principal \"\"; subaccount = null;}; token_name = \"ICPI\"; token_symbol = \"ICPI\"; decimals = 8; transfer_fee = 1000; })"

  dfx canister call token_icpi activity_start '(record {memo = opt "{op:mint,token:icpi}"; end_block_time = opt 1702393200000000000; amount = opt 100000000; max_amount = opt 100000000000; start_block_time = opt 1702383113000000000})'
}


if [ $network = "local" ]
then
deploy_local

else
  echo "need special network"
fi
