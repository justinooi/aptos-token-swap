module TokenSwap::swap {

    // Token Swap that allows someone to create a CoinStore of any token type (non-native), and in return allow others to swap for said non-native token for native Aptos token.

    // Imports
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::managed_coin;

    // Errors
    const ERROR: u64 = 0;


    // Coin Store Struct
    struct EscrowCoinStore<phantom CoinType> has store, key {
        escrow_store: coin::Coin<CoinType>,
        aptos_store: coin::Coin<AptosCoin>,
        price_per_token: u64,
    }

    public entry fun deposit_coinstore<CoinType>(account: &signer, amount: u64, cost: u64) acquires EscrowCoinStore {

        // get address of depositor
        let depositor = signer::address_of(account);

        // check if escrow coinstore for this coin has been initialized before
        if (exists<EscrowCoinStore<CoinType>>(depositor)) {

            // if exists, just add new deposit amount to the existing coinstore
            let existing_escrow = borrow_global_mut<EscrowCoinStore<CoinType>>(depositor);

            // get new deposit coinstore resource with amount they want to deposit
            let deposit = coin::withdraw<CoinType>(account, amount);

            // merge two deposit coinstore resources together to existing coinstore
            coin::merge<CoinType>(&mut existing_escrow.escrow_store, deposit);
        } else {

            // get deposit deposit coinstore resource
            let deposit = coin::withdraw<CoinType>(account, amount);

            // initialize aptos coinstore to receive aptos
            let aptos_init_cost = coin::withdraw<AptosCoin>(account, 1);

            // move escrowcoinstore resource to global state of account with the two
            // coinstores retrieved above
            move_to<EscrowCoinStore<CoinType>>(account, EscrowCoinStore { escrow_store: deposit, aptos_store: aptos_init_cost ,price_per_token: cost});
        }
    }

    public entry fun swap_token<CoinType>(swapper: &signer, coinstore_owner: address, amount: u64) acquires EscrowCoinStore {
        // get address of swapper
        let swapper_addr = signer::address_of(swapper);
        
        // ensure coinstore exist for said cointype
        assert!(exists<EscrowCoinStore<CoinType>>(coinstore_owner), ERROR);

        // get mutable escrow coin store resource to manipulate value
        let escrow = borrow_global_mut<EscrowCoinStore<CoinType>>(coinstore_owner);

        // get price per token
        let cost_multiplier = escrow.price_per_token;

        // get cost in aptos octas
        let final_cost = amount * cost_multiplier;
        let aptos_deposit = coin::withdraw<AptosCoin>(swapper, final_cost);

        // merge aptos coinstore together to get paid
        coin::merge<AptosCoin>(&mut escrow.aptos_store, aptos_deposit);

        // create token coinstore to send to swapper
        let to_send_to_swapper = coin::extract<CoinType>(&mut escrow.escrow_store, amount);
        coin::deposit<CoinType>(swapper_addr, to_send_to_swapper);
    }

    public entry fun withdraw_funds<CoinType>(coinstore_owner: &signer, amount: u64) acquires EscrowCoinStore {
        let owner_addr = signer::address_of(coinstore_owner);

         // ensure coinstore exist for said cointype
        assert!(exists<EscrowCoinStore<CoinType>>(owner_addr), ERROR);

        // get mutable escrow coin store resource to manipulate value
        let escrow = borrow_global_mut<EscrowCoinStore<CoinType>>(owner_addr);

        // withdraw coinstore
        let withdrawal_coinstore = coin::extract(&mut escrow.aptos_store, amount);
        coin::deposit<AptosCoin>(owner_addr, withdrawal_coinstore);
    }

    public entry fun update_price<CoinType>(coinstore_owner: &signer, new_price: u64) acquires EscrowCoinStore {
        let owner_addr = signer::address_of(coinstore_owner);
        assert!(exists<EscrowCoinStore<CoinType>>(owner_addr), ERROR);
        let escrow = borrow_global_mut<EscrowCoinStore<CoinType>>(owner_addr);
        escrow.price_per_token = new_price;
    }

    #[test_only]
    struct TestCoin {}

    // Deposit coin to coin store
    #[test(escrow_module = @TokenSwap)]
    public entry fun deposit_coins(escrow_module: signer) acquires EscrowCoinStore {
        let swapper = account::create_account_for_test(@0x3);
        let depositor = account::create_account_for_test(@0x2);
        let escrow_module = account::create_account_for_test(@0x4);
        
        managed_coin::initialize<AptosCoin>(&escrow_module, b"AptosCoin", b"APTOS", 6, false);

        managed_coin::register<AptosCoin>(&escrow_module);
        managed_coin::register<AptosCoin>(&depositor);
        managed_coin::register<AptosCoin>(&swapper);

        managed_coin::initialize<TestCoin>(&escrow_module, b"TestCoin", b"TEST", 6, false);

        managed_coin::register<TestCoin>(&escrow_module);
        managed_coin::register<TestCoin>(&depositor);
        managed_coin::register<TestCoin>(&swapper);

        let amount = 5000;
        let escrow_module_addr = signer::address_of(&escrow_module);
        let depositor_addr = signer::address_of(&depositor);
        let swapper_addr = signer::address_of(&swapper);

        managed_coin::mint<AptosCoin>(&escrow_module, escrow_module_addr, amount);
        managed_coin::mint<TestCoin>(&escrow_module, escrow_module_addr, amount);

        coin::transfer<AptosCoin>(&escrow_module, depositor_addr, 1000);
        coin::transfer<TestCoin>(&escrow_module, depositor_addr, 1000);

        coin::transfer<AptosCoin>(&escrow_module, swapper_addr, 1000);

        assert!(coin::balance<AptosCoin>(depositor_addr) == 1000, ERROR);
        assert!(coin::balance<TestCoin>(depositor_addr) == 1000, ERROR);

        deposit_coinstore<TestCoin>(&depositor, 500, 5);
        assert!(exists<EscrowCoinStore<TestCoin>>(depositor_addr), ERROR);

        swap_token<TestCoin>(&swapper, depositor_addr, 100);
        assert!(coin::balance<TestCoin>(swapper_addr) == 1000, ERROR);
    }
}