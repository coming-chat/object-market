// Copyright 2022 ComingChat Authors. Licensed under Apache-2.0 License.
#[test_only]
module object_market::market_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object::{Self, UID};
    use sui::transfer;

    use object_market::market::{
        Self, ObjectMarket
    };

    // Simple Dmens-NFT data structure.
    struct Dmens has key, store {
        id: UID,
        data: u8
    }

    fun burn_dmens(dmens: Dmens): u8 {
        let Dmens{ id, data } = dmens;
        object::delete(id);
        data
    }

    const ADMIN: address = @0xA55;
    const SELLER: address = @0x00A;
    const BUYER: address = @0x00B;

    /// Create a shared ObjectMarket.
    fun create_marketplace(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        market::create_market_for_testing<Dmens, SUI>(
            test_scenario::ctx(scenario)
        );
    }

    /// Mint SUI and send it to BUYER.
    fun mint_some_coin(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let coin = coin::mint_for_testing<SUI>(
            1000,
            test_scenario::ctx(scenario)
        );
        transfer::transfer(coin, BUYER);
    }

    /// Mint Dmens NFT and send it to SELLER.
    fun mint_dmens(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let nft = Dmens { id: object::new(test_scenario::ctx(scenario)), data: 1 };
        transfer::transfer(nft, SELLER);
    }

    // SELLER lists Dmens at the ObjectMarket for 100 SUI.
    fun list_dmens(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, SELLER);
        let obj_mkt = test_scenario::take_shared<ObjectMarket<Dmens, SUI>>(scenario);
        let nft = test_scenario::take_from_sender<Dmens>(scenario);

        market::list<Dmens, SUI>(&mut obj_mkt, nft, 100, test_scenario::ctx(scenario));

        test_scenario::return_shared(obj_mkt);
    }

    #[test]
    fun list_and_delist() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        create_marketplace(scenario);
        mint_dmens(scenario);
        list_dmens(scenario);

        test_scenario::next_tx(scenario, SELLER);
        {
            let obj_mkt = test_scenario::take_shared<ObjectMarket<Dmens, SUI>>(scenario);

            // Do the delist operation on a Marketplace.
            let nft = market::delist<Dmens, SUI>(
                &mut obj_mkt,
                0,
                test_scenario::ctx(scenario)
            );
            let data = burn_dmens(nft);

            assert!(data == 1, 0);

            test_scenario::return_shared(obj_mkt);
        };

        test_scenario::end(begin);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun fail_to_delist() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_dmens(scenario);
        list_dmens(scenario);

        // BUYER attempts to delist Dmens and he has no right to do so. :(
        test_scenario::next_tx(scenario, BUYER);
        {
            let obj_mkt = test_scenario::take_shared<ObjectMarket<Dmens, SUI>>(scenario);

            // Do the delist operation on a Marketplace.
            let nft = market::delist<Dmens, SUI>(
                &mut obj_mkt,
                0,
                test_scenario::ctx(scenario)
            );
            let _ = burn_dmens(nft);

            test_scenario::return_shared(obj_mkt);
        };

        test_scenario::end(begin);
    }

    #[test]
    fun buy_dmens() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_dmens(scenario);
        list_dmens(scenario);

        // BUYER takes 100 SUI from his wallet and purchases Dmens.
        test_scenario::next_tx(scenario, BUYER);
        {
            let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            let obj_mkt = test_scenario::take_shared<ObjectMarket<Dmens, SUI>>(scenario);
            let payment = coin::take(coin::balance_mut(&mut coin), 100, test_scenario::ctx(scenario));

            // Do the buy call and expect successful purchase.
            let nft = market::purchase<Dmens, SUI>(
                &mut obj_mkt,
                0,
                payment,
                test_scenario::ctx(scenario)
            );
            let data = burn_dmens(nft);

            assert!(data == 1, 0);

            test_scenario::return_shared(obj_mkt);
            test_scenario::return_to_sender(scenario, coin);
        };

        test_scenario::end(begin);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun fail_to_buy() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_dmens(scenario);
        list_dmens(scenario);

        // BUYER takes 100 SUI from his wallet and purchases Dmens.
        test_scenario::next_tx(scenario, BUYER);
        {
            let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            let obj_mkt = test_scenario::take_shared<ObjectMarket<Dmens, SUI>>(scenario);

            // AMOUNT here is 10 while expected is 100.
            let payment = coin::take(coin::balance_mut(&mut coin), 10, test_scenario::ctx(scenario));

            // Attempt to buy and expect failure purchase.
            let nft = market::purchase<Dmens, SUI>(
                &mut obj_mkt,
                0,
                payment,
                test_scenario::ctx(scenario)
            );
            let _ = burn_dmens(nft);

            test_scenario::return_shared(obj_mkt);
            test_scenario::return_to_sender(scenario, coin);
        };

        test_scenario::end(begin);
    }
}
