// Copyright 2023 ComingChat Authors. Licensed under Apache-2.0 License.
module marketplace::marketplace {
    use std::type_name::{into_string, get};
    use std::ascii::String;
    use std::vector;
    use sui::object::{Self, ID, UID, new, id};
    use sui::sui::SUI;
    use sui::balance::{Balance, zero, value, split, join};
    use sui::tx_context::{TxContext, sender};
    use sui::transfer::{public_transfer, public_share_object};
    use sui::object_table::{Self, ObjectTable};
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin, destroy_zero};
    use sui::event::emit;
    use sui::pay;

    use marketplace::royalty_fee::{RoyaltyBag, init_royalty_bag, charge_royalty};

    const BASE_BPS: u128 = 10000;
    const DEFAULT_FEE_BPS: u16 = 200; // 2%

    const ERR_NO_PERMISSION: u64 = 1;
    const ERR_MARKET_IS_PAUSED: u64 = 2;
    const ERR_NOT_OWNER: u64 = 3;
    const ERR_NOT_ENOUGH: u64 = 4;
    const ERR_UNEXPECT_FEE: u64 = 5;

    struct MarketplaceConfig has key,store {
        id: UID,
        is_paused: bool,
        fee_bps: u16,
        admin: address,
        beneficiary: address,
        balance: Balance<SUI>,
        list_items: ObjectTable<ID, Listing>
    }

    struct Listing has key, store {
        id: UID,
        price: u64,
        owner: address,
        nft_type: String
    }

    struct ListingEvent has copy, drop {
        item_id: ID,
        price: u64,
        seller: address,
        nft_type: String
    }

    struct ForceDeListEvent has copy, drop {
        item_id: ID,
        seller: address,
        nft_type: String
    }

    struct DeListEvent has copy, drop {
        item_id: ID,
        seller: address,
        nft_type: String
    }

    struct BuyEvent has copy, drop {
        item_id: ID,
        price: u64,
        royalty_fee: u64,
        service_fee: u64,
        received: u64,
        buyer: address,
        nft_type: String
    }

    struct ChangePriceEvent has copy, drop {
        item_id: ID,
        seller: address,
        new_price: u64
    }

    fun init(ctx: &mut TxContext) {
        public_share_object(
            MarketplaceConfig {
                id: new(ctx),
                is_paused: false,
                fee_bps: 500,
                admin: sender(ctx),
                beneficiary: @beneficiary,
                balance: zero(),
                list_items: object_table::new(ctx)
            }
        );

        init_royalty_bag(ctx)
    }

    #[test_only]
    public fun init_for_testing(
        beneficiary: address,
        ctx: &mut TxContext
    ) {
        public_share_object(
            MarketplaceConfig {
                id: new(ctx),
                is_paused: false,
                fee_bps: 200,
                admin: sender(ctx),
                beneficiary,
                balance: zero(),
                list_items: object_table::new(ctx)
            }
        );
        init_royalty_bag(ctx)
    }

    fun charge_service_fee(
        mc: &mut MarketplaceConfig,
        paid: u64,
        paid_coin: &mut Coin<SUI>,
        ctx: &mut TxContext
    ): u64 {
        let fee_value = (((paid as u128) * (mc.fee_bps as u128) / BASE_BPS) as u64);
        if (fee_value > 0) {
            let balance = coin::into_balance<SUI>(
                coin::split<SUI>(paid_coin, fee_value, ctx)
            );

            join(&mut mc.balance, balance);
        };

        return fee_value
    }

    public entry fun set_marketplace(
        mc: &mut MarketplaceConfig,
        new_admin: address,
        new_fee_bps: u16,
        ctx: &mut TxContext
    ) {
        assert!(mc.admin == sender(ctx), ERR_NO_PERMISSION);

        mc.admin = new_admin;
        mc.fee_bps = new_fee_bps
    }

    public entry fun set_status(
        mc: &mut MarketplaceConfig,
        is_pause: bool,
        ctx: &mut TxContext
    ) {
        assert!(mc.admin == sender(ctx), ERR_NO_PERMISSION);

        mc.is_paused = is_pause
    }

    public entry fun withdraw(
        mc: &mut MarketplaceConfig,
        ctx: &mut TxContext
    ) {
        assert!(mc.admin == sender(ctx) || mc.beneficiary == sender(ctx), ERR_NO_PERMISSION);

        let value = value(&mc.balance);
        if (value > 0) {
            let withdraw = coin::from_balance<SUI>(
                split(&mut mc.balance, value),
                ctx
            );

            public_transfer(
                withdraw,
                mc.beneficiary
            )
        }
    }

    public entry fun list<NftType: key + store>(
        mc: &mut MarketplaceConfig,
        item: NftType,
        price: u64,
        ctx: &mut TxContext
    ) {
        assert!(!mc.is_paused, ERR_MARKET_IS_PAUSED);

        let nft_type = into_string(get<NftType>());
        let seller = sender(ctx);

        let listing = Listing {
            id: new(ctx),
            price,
            owner: seller,
            nft_type
        };

        let item_id = id<NftType>(&item);

        // Attach Item to the Listing through listing.id;
        dof::add<bool, NftType>(&mut listing.id, true, item);

        object_table::add(&mut mc.list_items, item_id, listing);

        emit(ListingEvent {
            item_id,
            price,
            seller,
            nft_type
        })
    }

    public entry fun force_batch_delist<NftType: key + store>(
        mc: &mut MarketplaceConfig,
        item_ids: vector<ID>,
        ctx: &mut TxContext
    ) {
        assert!(mc.admin == sender(ctx), ERR_NO_PERMISSION);

        let (i, len) = (0u64, vector::length(&item_ids));
        while (i < len) {
            let item_id = vector::pop_back(&mut item_ids);

            let Listing{
                id,
                price: _price,
                owner,
                nft_type
            } = object_table::remove<ID, Listing>(&mut mc.list_items, item_id);

            let item = dof::remove<bool, NftType>(&mut id, true);
            public_transfer<NftType>(item, owner);
            object::delete(id);

            emit(ForceDeListEvent {
                item_id,
                seller: owner,
                nft_type
            });

            i = i + 1;
        }
    }

    public entry fun delist<NftType: key + store>(
        mc: &mut MarketplaceConfig,
        item_id: ID,
        ctx: &mut TxContext
    ) {
        let Listing{
            id,
            price: _price,
            owner,
            nft_type
        } = object_table::remove<ID, Listing>(&mut mc.list_items, item_id);

        assert!(owner == sender(ctx), ERR_NOT_OWNER);

        let item = dof::remove<bool, NftType>(&mut id, true);

        public_transfer<NftType>(item, owner);
        object::delete(id);

        emit(DeListEvent {
            item_id,
            seller: owner,
            nft_type
        })
    }

    public entry fun change_price<NftType: key + store>(
        mc: &mut MarketplaceConfig,
        item_id: ID,
        new_price: u64,
        ctx: &mut TxContext
    ) {
        assert!(!mc.is_paused, ERR_MARKET_IS_PAUSED);

        let listing = object_table::borrow_mut<ID, Listing>(&mut mc.list_items, item_id);

        assert!(listing.owner == sender(ctx), ERR_NOT_OWNER);

        listing.price = new_price;

        emit(ChangePriceEvent{
            item_id,
            seller: listing.owner,
            new_price
        })
    }

    public entry fun buy<NftType: key + store>(
        mc: &mut MarketplaceConfig,
        rb: &mut RoyaltyBag,
        item_id: ID,
        paid_coins: vector<Coin<SUI>>,
        ctx: &mut TxContext
    ) {
        assert!(!mc.is_paused, ERR_MARKET_IS_PAUSED);
        let buyer = sender(ctx);

        let merged_coin = vector::pop_back(&mut paid_coins);
        pay::join_vec(&mut merged_coin, paid_coins);

        let Listing{
            id,
            price,
            owner,
            nft_type
        } = object_table::remove<ID, Listing>(&mut mc.list_items, item_id);

        assert!(coin::value(&merged_coin) >= price, ERR_NOT_ENOUGH);

        // 1. service_fee
        let service_fee = charge_service_fee(mc, price, &mut merged_coin,ctx);

        // 2. royalty_fee
        let royalty_fee = charge_royalty<NftType>(rb, price, &mut merged_coin, ctx);

        // 3. received coin
        assert!(service_fee + royalty_fee < price, ERR_UNEXPECT_FEE);
        let received = price - service_fee - royalty_fee;
        public_transfer(
            coin::split<SUI>(&mut merged_coin, received, ctx),
            owner
        );

        // 4. remain coin
        if (coin::value(&merged_coin) > 0) {
            public_transfer(merged_coin, buyer)
        } else {
            destroy_zero(merged_coin)
        };

        // 5. nft item
        let item = dof::remove<bool, NftType>(&mut id, true);
        public_transfer<NftType>(item, buyer);
        object::delete(id);

        emit(BuyEvent{
            item_id,
            price,
            royalty_fee,
            service_fee,
            received,
            buyer,
            nft_type
        })
    }

}