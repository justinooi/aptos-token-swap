module TokenSwap::swap {

    // Token Swap that allows someone to create a CoinStore of any token type (non-native), and in return allow others to swap for said non-native token for native Aptos token.

    // Imports
    use std::signer;
    use std::string::String;
    use std::error;
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::managed_coin;
    use aptos_framework::event::{Self, EventHandle};

    struct EscrowEventStore has key {
        deposit_events: EventHandle<DepositEvent>,
    }

    struct EscrowCoinStore<phantom CoinType> has store, key {
        escrow_store: coin::Coin<CoinType>,
        aptos_store: coin::Coin<AptosCoin>,
        price_per_token: u64,
    }

    struct DepositEvent has drop, store {
        coin_type_info: TypeInfo,
        deposit_address: address,
        deposit_amount: u64,
    }

    public entry fun init_coinstore<CoinType>(account: &signer, amount: u64, cost: u64) acquires EscrowCoinStore {
        let depositor = signer::address_of(account);
        
        if (exists<EscrowCoinStore<CoinType>>(depositor)) {
            let existing_escrow = borrow_global_mut<EscrowCoinStore<CoinType>>(depositor);
            let deposit = coin::withdraw<CoinType>(account, amount);

            coin::merge<CoinType>(&mut existing_escrow.escrow_store, deposit);
        } else {
            let deposit = coin::withdraw<CoinType>(account, amount);
            let aptos_init_cost = coin::withdraw<AptosCoin>(account, 1);
            move_to<EscrowCoinStore<CoinType>>(account, EscrowCoinStore { escrow_store: deposit, aptos_store: aptos_init_cost ,price_per_token: cost});
        }
        // let escrow_events = borrow_global_mut<EscrowEventStore>(depositor);
        // event::emit_event<DepositEvent>(
        //     &mut escrow_events.deposit_events, DepositEvent {
        //         coin_type_info: type_info::type_of<CoinType>(),
        //         deposit_address: depositor,
        //         deposit_amount: amount,
        //     },
        // )
    }

    // Deposit coin to coin store
    #[test(account= @0x1)]
    public entry fun deposit_coins() acquires EscrowCoinStore {
        let depositor = account::create_account_for_test(@0x2);
        let faucet = account::create_account_for_test(@0x1);
        
        managed_coin::initialize<AptosCoin>(&faucet, b"AptosCoin", b"APTOS", 6, false);

        managed_coin::register<AptosCoin>(&faucet);
        managed_coin::register<AptosCoin>(&depositor);

        let amount = 1000;
        let faucet_addr = signer::address_of(&faucet);
        let depositor_addr = signer::address_of(&depositor);

        managed_coin::mint<AptosCoin>(&faucet, faucet_addr, amount);
        coin::transfer<AptosCoin>(&faucet, depositor_addr, 900);
        assert!(coin::balance<AptosCoin>(depositor_addr) == 900, 0);

        init_coinstore<AptosCoin>(&depositor, 500, 1);
        assert!(exists<EscrowCoinStore<AptosCoin>>(depositor_addr), 0);
    }
}