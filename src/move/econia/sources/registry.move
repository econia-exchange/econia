/// Manages registration capabilities and operations.
///
/// # Indexing
///
/// Custodian and underwriter capabilities IDs are 1-indexed, since they
/// are optional: an ID of 0 is thus reserved as a flag for when there
/// is no associated capability.
///
/// For consistency, market IDs are thus 1-indexed as well.
///
/// # Functions
///
/// ## Public getters
///
/// * `get_custodian_id()`
/// * `get_underwriter_id()`
///
/// ## Public registration functions
///
/// * `register_custodian_capability()`
/// * `register_underwriter_capability()`
///
/// # Complete docgen index
///
/// The below index is automatically generated from source code:
module econia::registry {

    // Uses >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::type_info;
    use econia::incentives;
    use econia::tablist::{Self, Tablist};
    use std::option::{Self, Option};
    use std::string::{Self, String};

    // Uses <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Test-only uses >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    #[test_only]
    use econia::assets::{Self, UC};

    // Test-only uses <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Structs >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Custodian capability required to approve order placement, order
    /// cancellation, and coin withdrawals. Administered to third-party
    /// registrants who may store it as they wish.
    struct CustodianCapability has store {
        /// Serial ID, 1-indexed, generated upon registration as a
        /// custodian.
        custodian_id: u64
    }

    /// Emitted when a capability is registered.
    struct CapabilityRegistrationEvent has drop, store {
        /// Either `CUSTODIAN` or `UNDERWRITER`, the capability type
        /// just registered.
        capability_type: bool,
        /// ID of capability just registered.
        capability_id: u64
    }

    /// Type flag for generic asset. Must be passed as base asset type
    /// argument for generic market operations.
    struct GenericAsset has key {}

    /// Information about a market.
    struct MarketInfo has copy, drop, store {
        /// Base asset type name. When base asset is an
        /// `aptos_framework::coin::Coin`, corresponds to the phantom
        /// `CoinType` (`address:module::MyCoin` rather than
        /// `aptos_framework::coin::Coin<address:module::MyCoin>`), and
        /// `underwriter_id` is none. Otherwise can be any value, and
        /// `underwriter` is some.
        base_type: String,
        /// Quote asset coin type name. Corresponds to a phantom
        /// `CoinType` (`address:module::MyCoin` rather than
        /// `aptos_framework::coin::Coin<address:module::MyCoin>`).
        quote_type: String,
        /// Number of base units exchanged per lot (when base asset is
        /// a coin, corresponds to `aptos_framework::coin::Coin.value`).
        lot_size: u64,
        /// Number of quote coin units exchanged per tick (corresponds
        /// to `aptos_framework::coin::Coin.value`).
        tick_size: u64,
        /// ID of underwriter capability required to verify generic
        /// asset amounts. A market-wide ID that only applies to markets
        /// having a generic base asset. None when base and quote types
        /// are both coins.
        underwriter_id: Option<u64>
    }

    /// Emitted when a market is registered.
    struct MarketRegistrationEvent has drop, store {
        /// Market ID of the market just registered.
        market_id: u64,
        /// Base asset type name.
        base_type: String,
        /// Quote asset type name.
        quote_type: String,
        /// Number of base units exchanged per lot.
        lot_size: u64,
        /// Number of quote units exchanged per tick.
        tick_size: u64,
        /// ID of `UnderwriterCapability` required to verify generic
        /// asset amounts. None when base and quote assets are both
        /// coins.
        underwriter_id: Option<u64>,
    }

    /// Emitted when a recognized market is added, removed, or updated.
    struct RecognizedMarketEvent has drop, store {
        /// The associated trading pair.
        trading_pair: TradingPair,
        /// The recognized market info for the given trading pair after
        /// an addition or update. None if a removal.
        recognized_market_info: Option<RecognizedMarketInfo>,
    }

    /// Recognized market info for a given trading pair.
    struct RecognizedMarketInfo has drop, store {
        /// Market ID of recognized market, 0-indexed.
        market_id: u64,
        /// Number of base units exchanged per lot.
        lot_size: u64,
        /// Number of quote units exchanged per tick.
        tick_size: u64,
        /// ID of underwriter capability required to verify generic
        /// asset amounts. A market-wide ID that only applies to
        /// markets having a generic base asset. None when base and
        /// quote types are both coins.
        underwriter_id: Option<u64>,
    }

    /// Recognized markets for specific trading pairs.
    struct RecognizedMarkets has key {
        /// Map from trading pair info to market information for the
        /// recognized market, if any, for given trading pair.
        map: Tablist<TradingPair, RecognizedMarketInfo>,
        /// Event handle for recognized market events.
        recognized_market_events: EventHandle<RecognizedMarketEvent>
    }

    /// Global registration information.
    struct Registry has key {
        /// Map from market info to corresponding 1-indexed market ID,
        /// enabling duplicate checks and iterated indexing.
        markets: Tablist<MarketInfo, u64>,
        /// The number of registered custodians.
        n_custodians: u64,
        /// The number of registered underwriters.
        n_underwriters: u64,
        /// Event handle for market registration events.
        market_registration_events: EventHandle<MarketRegistrationEvent>,
        /// Event handle for capability registration events.
        capability_registration_events:
            EventHandle<CapabilityRegistrationEvent>
    }

    /// A combination of a base asset and a quote asset.
    struct TradingPair has copy, drop, store {
        /// Base type name.
        base_type: String,
        /// Quote type name.
        quote_type: String
    }

    /// Underwriter capability required to verify generic asset
    /// amounts. Administered to third-party registrants who may store
    /// it as they wish.
    struct UnderwriterCapability has store {
        /// Serial ID, 1-indexed, generated upon registration as an
        /// underwriter.
        underwriter_id: u64
    }

    // Structs <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Error codes >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Base coin type has not been initialized for a pure coin market.
    const E_BASE_NOT_COIN: u64 = 0;
    /// Generic base asset descriptor has too few charaters.
    const E_GENERIC_TOO_FEW_CHARACTERS: u64 = 1;
    /// Generic base asset descriptor has too many charaters.
    const E_GENERIC_TOO_MANY_CHARACTERS: u64 = 2;
    /// Lot size specified as 0.
    const E_LOT_SIZE_0: u64 = 3;
    /// Tick size specified as 0.
    const E_TICK_SIZE_0: u64 = 4;
    /// Quote asset type has not been initialized as a coin.
    const E_QUOTE_NOT_COIN: u64 = 5;
    /// Base and quote asset descriptors are identical.
    const E_BASE_QUOTE_SAME: u64 = 6;
    /// Market is already registered.
    const E_MARKET_REGISTERED: u64 = 7;

    // Error codes <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Constants >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Flag for custodian capability.
    const CUSTODIAN: bool = true;
    /// Flag for underwriter capability.
    const UNDERWRITER: bool = false;
    /// Maximum number of characters permitted in a generic asset name,
    /// equal to the maximum number of characters permitted in a comment
    /// line per PEP 8.
    const MAX_CHARACTERS_GENERIC: u64 = 72;
    /// Minimum number of characters permitted in a generic asset name,
    /// equal to the number of spaces in an indentation level per PEP 8.
    const MIN_CHARACTERS_GENERIC: u64 = 4;

    // Constants <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Public functions >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Return serial ID of given `CustodianCapability`.
    ///
    /// # Testing
    ///
    /// * `test_register_capabilities()`
    public fun get_custodian_id(
        custodian_capability_ref: &CustodianCapability
    ): u64 {
        custodian_capability_ref.custodian_id
    }

    /// Return serial ID of given `UnderwriterCapability`.
    ///
    /// # Testing
    ///
    /// * `test_register_capabilities()`
    public fun get_underwriter_id(
        underwriter_capability_ref: &UnderwriterCapability
    ): u64 {
        underwriter_capability_ref.underwriter_id
    }

    /// Return a unique `CustodianCapability`.
    ///
    /// Increment the number of registered custodians, then issue a
    /// capability with the corresponding serial ID. Requires utility
    /// coins to cover the custodian registration fee.
    ///
    /// # Testing
    ///
    /// * `test_register_capabilities()`
    public fun register_custodian_capability<UtilityCoinType>(
        utility_coins: Coin<UtilityCoinType>
    ): CustodianCapability
    acquires Registry {
        // Borrow mutable reference to registry.
        let registry_ref_mut = borrow_global_mut<Registry>(@econia);
        // Set custodian serial ID to the new number of custodians.
        let custodian_id = registry_ref_mut.n_custodians + 1;
        // Update the registry for the new count.
        registry_ref_mut.n_custodians = custodian_id;
        incentives:: // Deposit provided utility coins.
            deposit_custodian_registration_utility_coins(utility_coins);
        // Pack and return corresponding capability.
        CustodianCapability{custodian_id}
    }

    /// Return a unique `UnderwriterCapability`.
    ///
    /// Increment the number of registered underwriters, then issue a
    /// capability with the corresponding serial ID. Requires utility
    /// coins to cover the underwriter registration fee.
    ///
    /// # Testing
    ///
    /// * `test_register_capabilities()`
    public fun register_underwriter_capability<UtilityCoinType>(
        utility_coins: Coin<UtilityCoinType>
    ): UnderwriterCapability
    acquires Registry {
        // Borrow mutable reference to registry.
        let registry_ref_mut = borrow_global_mut<Registry>(@econia);
        // Set underwriter serial ID to the new number of underwriters.
        let underwriter_id = registry_ref_mut.n_underwriters + 1;
        // Update the registry for the new count.
        registry_ref_mut.n_underwriters = underwriter_id;
        incentives:: // Deposit provided utility coins.
            deposit_underwriter_registration_utility_coins(utility_coins);
        // Pack and return corresponding capability.
        UnderwriterCapability{underwriter_id}
    }

    // Public functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Public friend functions >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Wrapped market registration call for a base coin type.
    ///
    /// See inner function `register_market_internal()`.
    ///
    /// # Aborts
    ///
    /// * `E_BASE_NOT_COIN`: Base coin type is not initialized.
    public(friend) fun register_market_base_coin_internal<
        BaseCoinType,
        QuoteCoinType,
        UtilityCoinType
    >(
        lot_size: u64,
        tick_size: u64,
        utility_coins: Coin<UtilityCoinType>
    ): u64
    acquires Registry {
        // Assert base coin type is initialized.
        assert!(coin::is_coin_initialized<BaseCoinType>(), E_BASE_NOT_COIN);
        // Add to the registry a corresponding entry, returnig new
        // market ID.
        register_market_internal<QuoteCoinType, UtilityCoinType>(
            type_info::type_name<BaseCoinType>(), lot_size, tick_size,
            option::none(), utility_coins)
    }

    /// Wrapped market registration call for a generic base type,
    /// requiring immutable reference to corresponding
    /// `UnderwriterCapability` for the market, and `base_type`
    /// descriptor.
    ///
    /// See inner function `register_market_internal()`.
    ///
    /// # Aborts
    ///
    /// * `E_GENERIC_TOO_FEW_CHARACTERS`: Asset descriptor is too short.
    /// * `E_GENERIC_TOO_MANY_CHARACTERS`: Asset descriptor is too long.
    public(friend) fun register_market_base_generic_internal<
        QuoteCoinType,
        UtilityCoinType
    >(
        base_type: String,
        lot_size: u64,
        tick_size: u64,
        underwriter_capability_ref: &UnderwriterCapability,
        utility_coins: Coin<UtilityCoinType>
    ): u64
    acquires Registry {
        // Assert generic base asset string is not too short.
        assert!(string::length(&base_type) >= MIN_CHARACTERS_GENERIC,
            E_GENERIC_TOO_FEW_CHARACTERS);
        // Assert generic base asset string is not too long.
        assert!(string::length(&base_type) <= MAX_CHARACTERS_GENERIC,
            E_GENERIC_TOO_MANY_CHARACTERS);
        // Get underwriter ID.
        let underwriter_id = get_underwriter_id(underwriter_capability_ref);
        // Add to the registry a corresponding entry, returnig new
        // market ID.
        register_market_internal<QuoteCoinType, UtilityCoinType>(
            base_type, lot_size, tick_size, option::some(underwriter_id),
            utility_coins)
    }

    // Public friend functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Private functions >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Initialize the Econia registry and recognized markets list upon
    /// module publication.
    fun init_module(
        econia: &signer
    ) {
        // Initialize registry.
        move_to(econia, Registry{
            markets: tablist::new(),
            n_custodians: 0,
            n_underwriters: 0,
            market_registration_events:
                account::new_event_handle<MarketRegistrationEvent>(econia),
            capability_registration_events:
                account::new_event_handle<CapabilityRegistrationEvent>(econia)
        });
        // Initialize recognized markets list.
        move_to(econia, RecognizedMarkets{
            map: tablist::new(),
            recognized_market_events:
                account::new_event_handle<RecognizedMarketEvent>(econia)
        });
    }

    /// Register a market in the global registry.
    ///
    /// # Type parameters
    ///
    /// * `QuoteCoinType`: The quote coin type for the market.
    /// * `UtilityCoinType`: The utility coin type.
    ///
    /// # Parameters
    ///
    /// * `base_type`: The base asset type. Should correspond to a coin
    ///   type if called by `register_market_base_coin_internal()`, else
    ///   provided by the market registrant.
    /// * `lot_size`: Lot size for the market.
    /// * `tick_size`: Tick size for the market.
    /// * `underwriter_id`: Optional underwriter ID for a market with a
    ///   generic base asset.
    /// * `utility_coins`: Utility coins paid to register a market.
    ///
    /// # Emits
    ///
    /// * `MarketRegistrationEvent`: Parameters of the market just
    ///   registered.
    ///
    /// # Aborts
    ///
    /// * `E_LOT_SIZE_0`: Lot size is 0.
    /// * `E_TICK_SIZE_0`: Tick size is 0.
    /// * `E_QUOTE_NOT_COIN`: Tick size is 0.
    /// * `E_BASE_QUOTE_SAME`: Base and quote type are the same.
    /// * `E_MARKET_REGISTERED`: Markets map already contains an entry
    ///   for specified market info.
    ///
    /// # Assumptions
    ///
    /// * `underwriter_id` has been properly packed and passed by either
    ///   `register_market_base_coin_internal` or
    ///   `register_market_base_generic_interal`.
    fun register_market_internal<
        QuoteCoinType,
        UtilityCoinType
    >(
        base_type: String,
        lot_size: u64,
        tick_size: u64,
        underwriter_id: Option<u64>,
        utility_coins: Coin<UtilityCoinType>
    ): u64
    acquires Registry {
        // Assert lot size is nonzero.
        assert!(lot_size > 0, E_LOT_SIZE_0);
        // Assert tick size is nonzero.
        assert!(tick_size > 0, E_TICK_SIZE_0);
        // Assert quote coin type is initialized.
        assert!(coin::is_coin_initialized<QuoteCoinType>(), E_QUOTE_NOT_COIN);
        // Get quote type name.
        let quote_type = type_info::type_name<QuoteCoinType>();
        // Assert base and quote type names are not the same.
        assert!(base_type != quote_type, E_BASE_QUOTE_SAME);
        let market_info = MarketInfo{ // Pack market info.
            base_type, quote_type, lot_size, tick_size, underwriter_id};
        // Mutably borrow registry.
        let registry_ref_mut = borrow_global_mut<Registry>(@econia);
        // Mutably borrow markets map.
        let markets_ref_mut = &mut registry_ref_mut.markets;
        assert!(!tablist::contains(markets_ref_mut, market_info),
            E_MARKET_REGISTERED); // Assert market not registered.
        // Get 1-indexed market ID.
        let market_id = tablist::length(markets_ref_mut) + 1;
        // Register a market entry.
        tablist::add(markets_ref_mut, market_info, market_id);
        // Emit a market registration event.
        event::emit_event(&mut registry_ref_mut.market_registration_events,
            MarketRegistrationEvent{market_id, base_type, quote_type,
                lot_size, tick_size, underwriter_id});
        incentives::deposit_market_registration_utility_coins<UtilityCoinType>(
                utility_coins); // Deposit utility coins.
        market_id // Return market ID.
    }

    // Private functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Test-only functions >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    #[test_only]
    /// Drop the given `CustodianCapability`.
    public fun drop_custodian_capability_test(
        custodian_capability: CustodianCapability
    ) {
        // Unpack provided capability.
        let CustodianCapability{custodian_id: _} = custodian_capability;
    }

    #[test_only]
    /// Drop the given `UnderwriterCapability`.
    public fun drop_underwriter_capability_test(
        underwriter_capability: UnderwriterCapability
    ) {
        // Unpack provided capability.
        let UnderwriterCapability{underwriter_id: _} = underwriter_capability;
    }

    #[test_only]
    /// Initialize registry for testing.
    public fun init_test() {
        // Get signer for Econia account.
        let econia = account::create_signer_with_capability(
            &account::create_test_signer_cap(@econia));
        // Create Aptos-style account for Econia.
        account::create_account_for_test(@econia);
        init_module(&econia); // Init registry.
    }

    // Test-only functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Tests >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    #[test]
    /// Verify custodian then underwriter capability registration.
    fun test_register_capabilities()
    acquires Registry {
        init_test(); // Init registry and recognized markets list.
        incentives::init_test(); // Initialize incentives parameters.
        // Get custodian registration fee.
        let custodian_registration_fee =
            incentives::get_custodian_registration_fee();
        // Get custodian capability.
        let custodian_capability = register_custodian_capability(
            assets::mint_test<UC>(custodian_registration_fee));
        // Assert it has ID 1.
        assert!(get_custodian_id(&custodian_capability) == 1, 0);
        // Drop custodian capability.
        drop_custodian_capability_test(custodian_capability);
        // Get another custodian capability.
        custodian_capability = register_custodian_capability(
            assets::mint_test<UC>(custodian_registration_fee));
        // Assert it has ID 2.
        assert!(get_custodian_id(&custodian_capability) == 2, 0);
        // Drop custodian capability.
        drop_custodian_capability_test(custodian_capability);
        // Get another custodian capability.
        custodian_capability = register_custodian_capability(
            assets::mint_test<UC>(custodian_registration_fee));
        // Assert it has ID 3.
        assert!(get_custodian_id(&custodian_capability) == 3, 0);
        // Drop custodian capability.
        drop_custodian_capability_test(custodian_capability);
        // Get underwriter registration fee.
        let underwriter_registration_fee =
            incentives::get_underwriter_registration_fee();
        // Get underwriter capability.
        let underwriter_capability = register_underwriter_capability(
            assets::mint_test<UC>(underwriter_registration_fee));
        // Assert it has ID 1.
        assert!(get_underwriter_id(&underwriter_capability) == 1, 0);
        // Drop underwriter capability.
        drop_underwriter_capability_test(underwriter_capability);
        // Get another underwriter capability.
        underwriter_capability = register_underwriter_capability(
            assets::mint_test<UC>(underwriter_registration_fee));
        // Assert it has ID 2.
        assert!(get_underwriter_id(&underwriter_capability) == 2, 0);
        // Drop underwriter capability.
        drop_underwriter_capability_test(underwriter_capability);
        // Get another underwriter capability.
        underwriter_capability = register_underwriter_capability(
            assets::mint_test<UC>(underwriter_registration_fee));
        // Assert it has ID 3.
        assert!(get_underwriter_id(&underwriter_capability) == 3, 0);
        // Drop underwriter capability.
        drop_underwriter_capability_test(underwriter_capability);
    }

    // Tests <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

}