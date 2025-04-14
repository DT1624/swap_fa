#[test_only]
module swap::swap_utils_test {
    use std::option;
    use std::signer;
    use swap::swap_pool;
    use swap::swap_utils;

    const ERROR_POOL_ADDRESS: u64 = 1;


    #[test(admin = @swap, user = @user)]
    fun test_init(admin: &signer, user: &signer) {
        swap_utils::init_for_test_untils(admin);
        swap_pool::init_for_test_pool(admin);
        swap_utils::init_FA(
            user,
            option::none(),
            b"USDT",
            b"USD",
            8,
            b"",
            b""
        );

        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        // let assets: SmartTable<vector<u8>, address> = swap_untils::get_global_state();
        // print(&swap_untils::exist_FA(b"USD"));
        // print(&swap_untils::exist_FA(b"BNB"));
        // let addr: address = swap_resource::get_address_FA(b"USD");
        // swap_resource::get_metadata(addr);
        //
        let addr_usd: address = swap_utils::get_address_FA(b"USD");
        let addr_bnb: address = swap_utils::get_address_FA(b"BNB");

        // print(&swap_untils::get_metadata(addr_bnb));
        // print(&swap_untils::get_symbol(addr_bnb));

        // let pa1: PairAsset = swap_resource::make_pair_asset(addr_usd, addr_bnb);
        // let pa2: PairAsset = swap_resource::make_pair_asset(addr_bnb, addr_usd);

        // print(&swap_untils::compare_pair_asset(pa1, pa2));
        // print(&swap_untils::exist_pair_asset(pa1));

        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );

        // print(&swap_untils::exist_FA(b"LP-BNB-USDt"));
        // print(&swap_untils::exist_pair_asset(pa2));
        // print(&swap_pool::is_exists_swapinfo(signer::address_of(user)));
        // print(&swap_pool::is_exists_swapinfo(signer::address_of(admin)));
        // print(&swap_pool::is_exist_swapinfo(signer::address_of()));

        // print(&swap_resource::resource_address());
        // assert!(!swap_pool::exists_token_pair_reserve(), ERROR_POOL_ADDRESS);
        // assert!(!swap_pool::exists_token_pair_metadata(), ERROR_POOL_ADDRESS);
    }

    #[test(creator = @swap, user = @user, user1 = @0xcafe)]
    fun test_mint(creator: &signer, user: &signer, user1: &signer) {
        swap_utils::init_for_test_untils(creator);
        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        let addr_bnb: address = swap_utils::get_address_FA(b"BNB");
        // print(&addr_bnb);
        let addr_receive: address = signer::address_of(user1);
        swap_utils::mint(user, addr_bnb, addr_receive, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_receive) == 10, 1);
        assert!(swap_pool::get_total_supply(addr_bnb) == 10, 1);
        swap_utils::mint(user, addr_bnb, signer::address_of(user), 111);
        assert!(swap_pool::get_total_supply(addr_bnb) == 121, 1);
    }


}
