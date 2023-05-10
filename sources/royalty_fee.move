// Copyright 2023 ComingChat Authors. Licensed under Apache-2.0 License.
module marketplace::royalty_fee {
    use std::ascii::String;
    use std::type_name::{into_string, get};
    use sui::object::{UID, new};
    use sui::tx_context::{TxContext, sender};
    use sui::transfer::{public_share_object, public_transfer};
    use sui::bag::{Self, Bag};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object;

    const BASE_BPS: u128 = 10000;

    const ERR_NO_PERMISSION: u64 = 1;

    struct RoyaltyBag has key,store {
        id: UID,
        admin: address,
        royalties: Bag
    }

    struct RoyaltyNftTypeItem has key,store {
        id: UID,
        nft_type: String,
        creator: address,
        bps: u16
    }

    public fun init_royalty_bag(ctx: &mut TxContext) {
        public_share_object(
            RoyaltyBag {
                id: new(ctx),
                admin: sender(ctx),
                royalties: bag::new(ctx)
            }
        )
    }

    public fun charge_royalty<NftType>(
        rb: &mut RoyaltyBag,
        paid: u64,
        paid_coin: &mut Coin<SUI>,
        ctx: &mut TxContext
    ): u64 {
        if (!bag::contains(&rb.royalties, into_string(get<NftType>()))) {
            return 0
        };

        let royalty_item = bag::borrow<String, RoyaltyNftTypeItem>(
            &rb.royalties,
            into_string(get<NftType>())
        );

        let royalty_value = (((paid as u128) * (royalty_item.bps as u128) / BASE_BPS) as u64);

        if (royalty_value > 0) {
            let royalty_fee = coin::split<SUI>(paid_coin, royalty_value, ctx);

            public_transfer(
                royalty_fee,
                royalty_item.creator
            )
        };

        return royalty_value
    }

    public entry fun set_admin(
        rb: &mut RoyaltyBag,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        assert!(rb.admin == sender(ctx), ERR_NO_PERMISSION);
        rb.admin = new_admin
    }

    public entry fun set_royalty<NftType>(
        rb: &mut RoyaltyBag,
        creator: address,
        bps: u16,
        ctx: &mut TxContext
    ) {
        assert!(rb.admin == sender(ctx), ERR_NO_PERMISSION);

        let nft_type = into_string(get<NftType>());
        let royalty_item = RoyaltyNftTypeItem {
            id: new(ctx),
            nft_type,
            creator,
            bps
        };

        if (bag::contains(&rb.royalties, nft_type)) {
            let RoyaltyNftTypeItem{
                id,
                nft_type: _,
                creator: _,
                bps: _
            } = bag::remove(&mut rb.royalties, nft_type);

            object::delete(id);
        };

        bag::add(&mut rb.royalties, nft_type, royalty_item)
    }
}