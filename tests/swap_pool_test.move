#[test_only]
module swap::swap_pool_test {
    use std::option;
    use std::signer;
    use aptos_std::debug::print;
    use aptos_framework::fungible_asset;
    use swap::swap_utils;
    use swap::swap_utils::{PairAsset};
    use swap::swap_pool;
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context::gas_unit_price;

    const ERROR_POOL_ADDRESS: u64 = 1;
    const ERROR_CREATE_PAIR: u64 = 2;

    #[test(creator = @swap)]
    fun test_init_module(creator: &signer) {
        swap_pool::init_for_test_pool(creator);
        assert!(swap_pool::exists_swap_info(), ERROR_POOL_ADDRESS);
        assert!(swap_pool::exists_global_pool(), ERROR_POOL_ADDRESS);
    }

    #[test(creator = @swap, user = @user)]
    #[expected_failure(abort_code = swap_pool::ERROR_SAME_FUNGIBLE_ASSET, location = swap_pool)]
    fun test_create_pair_same_fa(creator: &signer, user: &signer) {
        swap_pool::init_for_test_pool(creator);
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
        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_bnb
        );
    }

    #[test(creator = @swap, user = @user, user1 = @0x123, user2 = @0x234)]
    #[expected_failure(abort_code = swap_pool::ERROR_PAIR_ASSET_ALREADY_EXISTS, location = swap_pool)]
    fun test_create_exists_pair(creator: &signer, user: &signer, user1: &signer, user2: &signer) {
        swap_pool::init_for_test_pool(creator);
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
        swap_utils::init_FA(
            user,
            option::none(),
            b"USDT",
            b"USD",
            8,
            b"",
            b""
        );

        let addr_usd: address = swap_utils::get_address_FA(b"USD");
        let addr_bnb: address = swap_utils::get_address_FA(b"BNB");
        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );
        swap_pool::create_pair(
            user1,
            addr_usd,
            addr_bnb
        );
    }

    #[test(creator = @swap, user = @user, user1 = @0xcafe, aptos = @0x1)]
    fun test_add_liquidity(creator: &signer, user: &signer, user1: &signer, aptos: &signer) {
        timestamp::set_time_has_started_for_testing(aptos);
        swap_utils::init_for_test_untils(creator);
        swap_pool::init_for_test_pool(creator);
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
        let addr_usd: address = swap_utils::get_address_FA(b"USD");
        let addr_bnb: address = swap_utils::get_address_FA(b"BNB");

        let addr_user: address = signer::address_of(user);
        let addr_user1: address = signer::address_of(user1);

        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );

        let pa: PairAsset = swap_utils::make_pair_asset(addr_bnb, addr_usd);
        assert!(swap_pool::is_contain(pa), ERROR_CREATE_PAIR);

        let addr_pa: address = swap_utils::get_address_pair_asset(pa);

        // mint to user
        swap_utils::mint(user, addr_bnb, addr_user, 100);
        swap_utils::mint(user, addr_usd, addr_user, 200);
        assert!(swap_pool::get_balance(addr_bnb, addr_user) == 100, 1);
        assert!(swap_pool::get_balance(addr_usd, addr_user) == 200, 2);

        // mint to user 1
        swap_utils::mint(user, addr_bnb, addr_user1, 100);
        swap_utils::mint(user, addr_usd, addr_user1, 80);
        assert!(swap_pool::get_balance(addr_bnb, addr_user1) == 100, 3);
        assert!(swap_pool::get_balance(addr_usd, addr_user1) == 80, 4);
        // check total supply each FA
        assert!(swap_pool::get_total_supply(addr_bnb) == 200, 5);
        assert!(swap_pool::get_total_supply(addr_usd) == 280, 6);
        // check amount pa in each user's store
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 0, 7);
        assert!(swap_pool::get_balance(addr_pa, addr_user1) == 0, 8);
        // check total supply pa
        assert!(swap_pool::get_total_supply(addr_pa) == 0, 9);

        swap_pool::test_add_liquidity(user, pa, 80, 50);

        swap_pool::test_add_liquidity(user1, pa, 20, 60);
        assert!(swap_pool::get_total_supply(addr_bnb) == 200, 5);
        assert!(swap_pool::get_total_supply(addr_usd) == 280, 6);

        print(&swap_pool::get_balance(addr_bnb, addr_user));
        print(&swap_pool::get_balance(addr_usd, addr_user));
        print(&swap_pool::get_total_supply(addr_pa));
        print(&swap_pool::get_balance(addr_pa, addr_user));
        print(&swap_pool::get_balance(addr_pa, addr_user1));
        let (a, b) = swap_pool::get_token_pair_metadata(pa);
        print(&fungible_asset::balance(a));
        print(&swap_pool::get_balance(addr_bnb, addr_pa));
    }
}
