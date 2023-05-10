// Copyright 2023 ComingChat Authors. Licensed under Apache-2.0 License.
#[test_only]
module marketplace::marketplace_test {
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID, id};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario, ctx};
    use sui::transfer;
    
    use marketplace::marketplace::{
        init_for_testing, MarketplaceConfig, list, delist, buy, withdraw
    };
    use marketplace::royalty_fee::{RoyaltyBag, set_royalty};

    // For Test
    struct SuiCat has key, store {
        id: UID,
    }

    const ADMIN: address = @0xA55;
    const SELLER: address = @0x00A;
    const BUYER: address = @0x00B;
    const BENEFICIARY: address = @0x00C;

    /// Mint SUI and send it to BUYER.
    fun mint_some_coin(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let coin = coin::mint_for_testing<SUI>(
            100000,
            test_scenario::ctx(scenario)
        );
        transfer::public_transfer(coin, BUYER);
    }

    /// Mint SuiCat and send it to SELLER.
    fun mint_suicat(scenario: &mut Scenario): ID {
        test_scenario::next_tx(scenario, ADMIN);
        let nft = SuiCat { id: object::new(test_scenario::ctx(scenario)) };
        let id = id(&nft);
        transfer::public_transfer(nft, SELLER);

        return id
    }

    // SELLER lists SuiCat at the ObjectMarket for 10000 MIST.
    fun list_suicat(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, SELLER);
        let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);
        let nft = test_scenario::take_from_sender<SuiCat>(scenario);

        list<SuiCat>(&mut marketplace, nft, 10000, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace);
    }

    #[test]
    fun list_and_delist() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        init_for_testing(BENEFICIARY, ctx(scenario));
        let item_id = mint_suicat(scenario);
        list_suicat(scenario);

        test_scenario::next_tx(scenario, SELLER);
        {
            let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);

            // Do the delist operation on a Marketplace.
            delist<SuiCat>(
                &mut marketplace,
                item_id,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(marketplace);
        };

        test_scenario::next_tx(scenario, SELLER);
        {
            let suicat = test_scenario::take_from_sender<SuiCat>(scenario);
            test_scenario::return_to_sender(scenario, suicat)
        };

        test_scenario::end(begin);
    }

    #[test]
    #[expected_failure(abort_code = marketplace::marketplace::ERR_NOT_OWNER)]
    fun fail_to_delist() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        init_for_testing(BENEFICIARY, ctx(scenario));
        mint_some_coin(scenario);
        let item_id = mint_suicat(scenario);
        list_suicat(scenario);

        // BUYER attempts to delist Dmens and he has no right to do so. :(
        test_scenario::next_tx(scenario, BUYER);
        {
            let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);

            // Do the delist operation on a Marketplace.
            delist<SuiCat>(
                &mut marketplace,
                item_id,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(marketplace);
        };

        test_scenario::end(begin);
    }

    #[test]
    fun buy_suicat() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        init_for_testing(BENEFICIARY, ctx(scenario));
        mint_some_coin(scenario);
        let item_id = mint_suicat(scenario);
        list_suicat(scenario);

        test_scenario::next_tx(scenario, ADMIN);
        {
            let royaltybag = test_scenario::take_shared<RoyaltyBag>(scenario);
            set_royalty<SuiCat>(&mut royaltybag, ADMIN, 500, ctx(scenario));
            test_scenario::return_shared(royaltybag);
        };

        // BUYER takes 10000 SUI from his wallet and purchases Dmens.
        test_scenario::next_tx(scenario, BUYER);
        {
            let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);
            let royaltybag = test_scenario::take_shared<RoyaltyBag>(scenario);
            let payment = coin::take(coin::balance_mut(&mut coin), 10000, test_scenario::ctx(scenario));

            // Do the buy call and expect successful purchase.
            buy<SuiCat>(
                &mut marketplace,
                &mut royaltybag,
                item_id,
                vector<Coin<SUI>>[payment],
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(royaltybag);
            test_scenario::return_shared(marketplace);
            test_scenario::return_to_sender(scenario, coin);
        };

        test_scenario::next_tx(scenario, BENEFICIARY);
        {
            let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);

            // withdraw fee
            withdraw(
                &mut marketplace,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(marketplace);
        };

        test_scenario::next_tx(scenario, BENEFICIARY);
        {
            let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);

            let fee_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            assert!(coin::value(&fee_coin) == 200, 1);

            test_scenario::return_shared(marketplace);
            test_scenario::return_to_sender(scenario, fee_coin);
        };

        test_scenario::next_tx(scenario, ADMIN);
        {
            let royalty_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);

            assert!(coin::value(&royalty_coin) == 500, 2);

            test_scenario::return_to_sender(scenario, royalty_coin);
        };

        test_scenario::end(begin);
    }

    #[test]
    #[expected_failure(abort_code = marketplace::marketplace::ERR_NOT_ENOUGH)]
    fun fail_to_buy() {
        let begin = test_scenario::begin(ADMIN);
        let scenario = &mut begin;

        init_for_testing(BENEFICIARY, ctx(scenario));
        mint_some_coin(scenario);
        let item_id = mint_suicat(scenario);
        list_suicat(scenario);

        // BUYER takes 10000 SUI from his wallet and purchases Dmens.
        test_scenario::next_tx(scenario, BUYER);
        {
            let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            let marketplace = test_scenario::take_shared<MarketplaceConfig>(scenario);
            let royaltybag = test_scenario::take_shared<RoyaltyBag>(scenario);

            // AMOUNT here is 10 while expected is 10000.
            let payment = coin::take(coin::balance_mut(&mut coin), 10, test_scenario::ctx(scenario));

            // Attempt to buy and expect failure purchase.
            buy<SuiCat>(
                &mut marketplace,
                &mut royaltybag,
                item_id,
                vector<Coin<SUI>>[payment],
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(royaltybag);
            test_scenario::return_shared(marketplace);
            test_scenario::return_to_sender(scenario, coin);
        };

        test_scenario::end(begin);
    }
}