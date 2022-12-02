// Copyright 2022 ComingChat Authors. Licensed under Apache-2.0 License.

/// ObjectMarket - a unique object trading marketplace in the Sui network.
///
/// The structure of the markeptlace storage is the following:
/// ```
///                       /+---(index #1)--> Listing<T1,C1>(Item, Price...)
/// ( ObjectMarket<T1,C1> ) +---(index #2)--> Listing<T1,C1>(Item, Price...)
///                       \+---(index #N)--> Listing<T1,C1>(Item, Price...)
///
///                       /+---(index #1)--> Listing<T2,C2>(Item, Price...)
/// ( ObjectMarket<T2,C2> ) +---(index #2)--> Listing<T2,C2>(Item, Price...)
///                       \+---(index #N)--> Listing<T2,C2>(Item, Price...)
/// ```
module object_market::market {
    use std::ascii::String;
    use std::type_name::{into_string, get};

    use sui::balance::{Self, Balance, zero};
    use sui::coin::{Self, Coin};
    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::object_table::{Self, ObjectTable};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // 2.5% = 250/10000
    const FEE_POINT: u8 = 250;

    // For when someone tries to delist without ownership.
    const ERR_NOT_OWNER: u64 = 1;
    // For when amount paid does not match the expected.
    const ERR_AMOUNT_INCORRECT: u64 = 2;

    // ======= Types =======

    /// A Capability for market manager.
    struct MarketManagerCap has key, store {
        id: UID
    }

    /// A generic market for anything.
    struct ObjectMarket<T: key + store, phantom C> has key {
        id: UID,
        next_index: u64,
        beneficiary: address,
        fee: Balance<C>,
        items: ObjectTable<u64, Listing<T, C>>
    }

    /// A listing for the market.
    struct Listing<T: key + store, phantom C> has key, store {
        id: UID,
        item: T,
        price: u64,
        owner: address,
    }

    // ======= Events =======

    /// Emitted when a new ObjectMarket is created.
    struct MarketCreated<phantom T, phantom C> has copy, drop {
        market_id: ID,
        object: String,
        coin: String
    }

    /// Emitted when someone lists a new item on the ObjectMarket<T>.
    struct ItemListed<phantom C> has copy, drop {
        index: u64,
        item_id: ID,
        coin: String,
        price: u64,
        owner: address,
    }

    /// Emitted when owner delists an item from the ObjectMarket<T>.
    struct ItemDelisted<phantom C> has copy, drop {
        index: u64,
        item_id: ID,
        coin: String,
    }

    /// Emitted when someone makes a purchase. `new_owner` shows
    /// who is the new owner of the purchased asset.
    struct ItemPurchased<phantom C> has copy, drop {
        index: u64,
        item_id: ID,
        new_owner: address,
        coin: String,
    }

    // ======= Publishing =======

    fun init(ctx: &mut TxContext) {
        transfer::transfer(
            MarketManagerCap {
                id: object::new(ctx)
            },
            tx_context::sender(ctx)
        )
    }

    #[test_only]
    public fun create_market_for_testing<T: key + store, C>(
        beneficiary: address,
        ctx: &mut TxContext
    ) {
        publish<T, C>(ctx, beneficiary)
    }

    /// Admin-only method which allows market creation.
    public entry fun create_market<T: key + store, C>(
        _: &MarketManagerCap,
        ctx: &mut TxContext
    ) {
        publish<T, C>(ctx, @beneficiary)
    }

    /// Create and share a new `ObjectMarket` for the type `T`. Method is private
    /// and can only be called in the module initializer or in the admin-only
    /// method `create_market`.
    fun publish<T: key + store, C>(
        ctx: &mut TxContext,
        beneficiary: address
    ) {
        let id = object::new(ctx);
        emit(MarketCreated<T, C> {
            market_id: object::uid_to_inner(&id),
            object: into_string(get<T>()),
            coin: into_string(get<C>())
        });
        transfer::share_object(
            ObjectMarket<T, C> {
                id,
                next_index: 0,
                beneficiary,
                fee: zero<C>(),
                items: object_table::new<u64, Listing<T, C>>(ctx)
            }
        );
    }

    // ======= ObjectMarket Actions =======

    /// List a new item on the `ObjectMarket`.
    public entry fun list<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        item: T,
        price: u64,
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);
        let item_id = object::id(&item);
        let owner = tx_context::sender(ctx);

        emit(ItemListed<C> {
            index: market.next_index,
            item_id: *&item_id,
            coin: into_string(get<C>()),
            price,
            owner
        });

        object_table::add(
            &mut market.items,
            market.next_index,
            Listing<T, C> { id, item, price, owner }
        );

        market.next_index = market.next_index + 1;
    }

    /// Remove listing and get an item back. Can only be performed by the `owner`.
    public fun delist<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        item_index: u64,
        ctx: &mut TxContext
    ): T {
        let Listing { id, item, price: _, owner } = object_table::remove<u64, Listing<T, C>>(
            &mut market.items,
            item_index
        );

        assert!(tx_context::sender(ctx) == owner, ERR_NOT_OWNER);

        emit(ItemDelisted<C> {
            index: item_index,
            item_id: object::id(&item),
            coin: into_string(get<C>()),
        });

        object::delete(id);
        item
    }

    /// Call [`delist`] and transfer item to the sender.
    public entry fun delist_and_take<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        item_index: u64,
        ctx: &mut TxContext
    ) {
        transfer::transfer(
            delist(market, item_index, ctx),
            tx_context::sender(ctx)
        )
    }

    /// Purchase an asset by the `item_id`. Payment is done in Coin<C>.
    /// Paid amount must match the requested amount. If conditions are met,
    /// the owner of the item gets the payment and the buyer receives their item.
    public fun purchase<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        item_index: u64,
        paid: Coin<C>,
        ctx: &mut TxContext
    ): T {
        let Listing { id, item, price, owner } = object_table::remove<u64, Listing<T, C>>(
            &mut market.items,
            item_index
        );
        let new_owner = tx_context::sender(ctx);

        assert!(price == coin::value(&paid), ERR_AMOUNT_INCORRECT);

        emit(ItemPurchased<C> {
            index: item_index,
            item_id: object::id(&item),
            coin: into_string(get<C>()),
            new_owner
        });

        // handle 2.5% fee
        let fee = coin::value(&paid) / 10000 * (FEE_POINT as u64);
        if (fee > 0) {
            let fee_balance = coin::into_balance(coin::split(&mut paid, fee, ctx));
            balance::join(&mut market.fee, fee_balance);
        };

        transfer::transfer(paid, owner);

        object::delete(id);

        item
    }

    /// Call [`buy`] and transfer item to the sender.
    public entry fun purchase_and_take<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        item_index: u64,
        paid: Coin<C>,
        ctx: &mut TxContext
    ) {
        transfer::transfer(
            purchase(market, item_index, paid, ctx),
            tx_context::sender(ctx)
        )
    }

    /// Use `&mut Coin<C>` to purchase `T` from market.
    public entry fun purchase_and_take_mut<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        item_index: u64,
        paid: &mut Coin<C>,
        ctx: &mut TxContext
    ) {
        let listing = object_table::borrow<u64, Listing<T, C>>(&market.items, *&item_index);
        let coin = coin::split(paid, listing.price, ctx);
        purchase_and_take(market, item_index, coin, ctx)
    }

    /// Withdraw fee coins by beneficiary
    public entry fun withdraw<T: key + store, C>(
        market: &mut ObjectMarket<T, C>,
        ctx: &mut TxContext
    ) {
        assert!(
            market.beneficiary == tx_context::sender(ctx),
            ERR_NOT_OWNER
        );

        let fee = balance::value(&market.fee);
        let fee_balance = balance::split<C>(&mut market.fee, fee);

        transfer::transfer(
            coin::from_balance(fee_balance, ctx),
            tx_context::sender(ctx)
        )
    }
}
