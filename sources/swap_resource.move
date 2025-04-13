module swap::swap_resource {

    use std::option::Option;
    use std::signer;
    use std::string::{String, utf8};
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_std::smart_vector::singleton;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, MintRef, BurnRef};
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_framework::primary_fungible_store;


    /* constant parameters */
    const ADDRESS_RESOURCE: address = @swap;
    const RESOURCE_SEED: vector<u8> = b"RESOURCE";
    const SYMBOL_RESOURCE: vector<u8> = b"FA LP";
    const SYMBOL_USERS: vector<u8> = b"Users Management";


    /* constant errors */

    const ERROR_NOT_ADMIN_RESOURCE: u64 = 1;

    /* struct */
    struct AssetRegistry has store {
        fa_map: SmartTable<vector<u8>, address>,
        lp_map: SmartTable<vector<u8>, address>,
    }

    struct PairAsset has copy, drop, store {
        token_x: address,
        token_y: address,
    }

    struct PoolRegistry has store {
        pool_map: SmartTable<PairAsset, address>,
    }

    struct GlobalState has key {
        assets: AssetRegistry,
        pools: PoolRegistry,
    }

    fun init_module(admin: &signer) {
        let asset_registry: AssetRegistry = AssetRegistry {
            fa_map: smart_table::new(),
            lp_map: smart_table::new()
        };

        let pool_registry: PoolRegistry = PoolRegistry {
            pool_map: smart_table::new()
        };

        let constructor_ref: &ConstructorRef = &object::create_named_object(admin, SYMBOL_RESOURCE);
        let resource_signer: signer = object::generate_signer(constructor_ref);

        move_to(
            &resource_signer,
            GlobalState {
                assets: asset_registry,
                pools: pool_registry
            }
        );
    }

    public fun init_FA(
        admin: &signer,
        max_supply: Option<u128>,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        icon_uri: vector<u8>,
        project_uri: vector<u8>,
    ) acquires GlobalState {
        let constructor_ref: &ConstructorRef = &object::create_named_object(admin, symbol);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            max_supply,
            utf8(name),
            utf8(symbol),
            decimals,
            utf8(icon_uri),
            utf8(project_uri),
        );

        let addr: address = object::create_object_address(&signer::address_of(admin), symbol);
        add_fa_map(symbol, addr);
    }

    public fun init_LP(
        admin: &signer,
        constructor_ref: &ConstructorRef,
        max_supply: Option<u128>,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        icon_uri: vector<u8>,
        project_uri: vector<u8>,
    ) acquires GlobalState {
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            max_supply,
            utf8(name),
            utf8(symbol),
            decimals,
            utf8(icon_uri),
            utf8(project_uri),
        );

        let addr: address = object::create_object_address(&signer::address_of(admin), symbol);
        add_fa_map(symbol, addr);
        add_lp_map(symbol, signer::address_of(admin));
    }

    public fun resource_address(): address {
        object::create_object_address(&ADDRESS_RESOURCE, SYMBOL_RESOURCE)
    }

    public fun exist_data(admin: &signer): bool {
        let admin_address: address = signer::address_of(admin);
        exists<GlobalState>(admin_address)
    }

    public fun exist_FA(fa: vector<u8>): bool acquires GlobalState {
        let fa_map = &borrow_global<GlobalState>(resource_address()).assets.fa_map;
        fa_map.contains(fa)
    }

    public fun exists_pair_asset(pa: PairAsset): bool acquires GlobalState {
        let pool_map: &SmartTable<PairAsset, address> = &borrow_global<GlobalState>(resource_address()).pools.pool_map;
        pool_map.contains(pa)
    }

    public fun get_address_FA(fa: vector<u8>): address acquires GlobalState {
        *borrow_global<GlobalState>(resource_address()).assets.fa_map.borrow(fa)
    }

    public fun make_pair_asset(addr1: address, addr2: address): PairAsset {
        PairAsset {
            token_x: addr1,
            token_y: addr2
        }
    }

    public fun compare_pair_asset(pa1: PairAsset, pa2: PairAsset): bool {
        (pa1.token_x == pa2.token_x && pa1.token_y == pa2.token_y) || (pa1.token_y == pa2.token_x && pa1.token_x == pa2.token_y)
    }

    public fun get_object_metadata(addr: address): Object<Metadata> {
        object::address_to_object(addr)
    }

    public fun get_metadata(addr: address): Metadata {
        let metadata_object: Object<Metadata> = object::address_to_object(addr);
        let metadata: Metadata = fungible_asset::metadata(metadata_object);
        metadata
    }

    public fun get_symbol(addr: address): String {
        let metadata_object: Object<Metadata> = object::address_to_object(addr);
        fungible_asset::symbol(metadata_object)
    }

    public fun get_name(addr: address): String {
        let metadata_object: Object<Metadata> = object::address_to_object(addr);
        fungible_asset::name(metadata_object)
    }

    public fun add_pool_map(pa: PairAsset, addr: address) acquires GlobalState {
        let global_state: &mut GlobalState = borrow_global_mut<GlobalState>(resource_address());
        global_state.pools.pool_map.add(pa, addr);
    }

    public fun add_fa_map(symbol: vector<u8>, addr: address) acquires GlobalState {
        let global_state: &mut GlobalState = borrow_global_mut<GlobalState>(resource_address());
        global_state.assets.fa_map.add(symbol, addr);
    }

    public fun add_lp_map(symbol: vector<u8>, addr: address) acquires GlobalState {
        let global_state: &mut GlobalState = borrow_global_mut<GlobalState>(resource_address());
        global_state.assets.lp_map.add(symbol, addr);
    }

    public fun get_address_pair_asset(pa: PairAsset): address acquires GlobalState {
        *borrow_global<GlobalState>(resource_address()).pools.pool_map.borrow(pa)
    }

    public fun get_creator_pair_asset(symbol: vector<u8>): address acquires GlobalState {
        *borrow_global<GlobalState>(resource_address()).assets.lp_map.borrow(symbol)
    }

    public fun get_addres_pa_x_y(pa: PairAsset): (address, address){
        (pa.token_x, pa.token_y)
    }




    #[test_only]
    public fun init_for_test_resource(admin: &signer) {
        init_module(admin);
    }
}