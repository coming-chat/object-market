# ObjectMarket

Object Market is a unique object trading marketplace in the Sui network. 

## Core Object

- `module marketplace`

```move
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
```

- `module royalty`

```move
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
```

## Public entry function
- `module marketplace`

```move
// set marketplace config
// called by admin
public entry fun set_marketplace(
    mc: &mut MarketplaceConfig,
    new_admin: address,
    new_fee_bps: u16,
    ctx: &mut TxContext
);

// for emergency pause marketplace
// list,buy,change_price will be paused
// delist, force_batch_delist will be still available
// called by admin
public entry fun set_status(
    mc: &mut MarketplaceConfig,
    is_pause: bool,
    ctx: &mut TxContext
);

// force delist nft items
// called by admin
public entry fun force_batch_delist<NftType: key + store>(
    mc: &mut MarketplaceConfig,
    item_ids: vector<ID>,
    ctx: &mut TxContext
);

// list nft item
// called by user
public entry fun list<NftType: key + store>(
    mc: &mut MarketplaceConfig,
    item: NftType,
    price: u64,
    ctx: &mut TxContext
);

// delist nft item
// called by user
public entry fun delist<NftType: key + store>(
    mc: &mut MarketplaceConfig,
    item_id: ID,
    ctx: &mut TxContext
);

// change nft item price
// called by user
public entry fun change_price<NftType: key + store>(
    mc: &mut MarketplaceConfig,
    item_id: ID,
    new_price: u64,
    ctx: &mut TxContext
);

// buy nft item
// called by user
public entry fun buy<NftType: key + store>(
    mc: &mut MarketplaceConfig,
    rb: &mut RoyaltyBag,
    item_id: ID,
    paid_coins: vector<Coin<SUI>>,
    ctx: &mut TxContext
)

```

- `module royalty_fee`

```move
// set new admin
// called by admin
public entry fun set_admin(
    rb: &mut RoyaltyBag,
    new_admin: address,
    ctx: &mut TxContext
);

// set nft collection royalty
// called by admin
public entry fun set_royalty<NftType>(
    rb: &mut RoyaltyBag,
    creator: address,
    bps: u16,
    ctx: &mut TxContext
);
```