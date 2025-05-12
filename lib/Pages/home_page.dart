import 'package:animation_wrappers/animation_wrappers.dart';
import 'package:flutter/material.dart';
import 'package:hungerz_kiosk/Pages/orderPlaced.dart';
import 'package:hungerz_kiosk/Pages/item_info.dart';
import '../Components/custom_circular_button.dart';
import '../Theme/colors.dart';
import '../Models/menu_item.dart'; // Import MenuItem model
import '../Services/api_service.dart'; // Import ApiService
import '../Services/socket_service.dart';
import 'dart:async'; // Import for Future & StreamSubscription
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:hungerz_kiosk/ViewModels/home_page_view_model.dart'; // Import ViewModel
// import 'package:shared_preferences/shared_preferences.dart'; // Not needed directly

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

// Keep ItemCategory for the hardcoded list driving the UI
class ItemCategory {
  String image;
  String? name;

  ItemCategory(this.image, this.name);
}

class _HomePageState extends State<HomePage> {
  // Service instances
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService(); // Use singleton instance

  // State variables for fetched data, loading, and errors
  List<MenuItem> _displayedItems = [];
  Map<String, List<MenuItem>> _cachedItems = {}; 
  bool _isLoading = false;
  String? _fetchErrorMessage;

  int orderingIndex = 0; // 0 for Take Away, 1 for Dine In
  bool itemSelected = false; // Tracks if any item has count > 0
  MenuItem? _itemForInfoDrawer;
  int drawerCount = 0; // 0 for cart drawer, 1 for item info
  int currentIndex = 0; // For category selection
  PageController _pageController = PageController();
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  // State variables for socket connection and session
  bool _socketConnected = false;
  String? _socketErrorMsg;
  String? _currentSessionId; // Track session ID locally in the page state
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _sessionStartSubscription;
  StreamSubscription? _sessionEndSubscription;

  String? _currentlyFetchingCategory; // Add this line

  final List<ItemCategory> foodCategories = [
    ItemCategory('assets/ItemCategory/burger.png', "burgers"),
    ItemCategory('assets/ItemCategory/pizza.png', "pizzas"),
    ItemCategory('assets/ItemCategory/pates.png', "pates"),
    ItemCategory('assets/ItemCategory/kebbabs.png', "kebabs"),
    ItemCategory('assets/ItemCategory/tacos.png', "tacos"),
    ItemCategory('assets/ItemCategory/poulet.png', "poulet"),
    ItemCategory('assets/ItemCategory/healthy.png', "healthy"),
    ItemCategory('assets/ItemCategory/traditional.png', "traditional"),
    ItemCategory('assets/ItemCategory/dessert.png', "dessert"),
    ItemCategory('assets/ItemCategory/sandwitch.jpg', "sandwich"),
  ];

  @override
  void initState() {
    super.initState();
    
    // Initialize local state from SocketService
    _socketConnected = _socketService.isConnected;
    _currentSessionId = _socketService.sessionId;

    // Listen to socket events to update local state
    _listenToSocketEvents();
    
    // Fetch the first category when the page loads
    if (foodCategories.isNotEmpty && foodCategories[0].name != null) {
      _fetchMenuItems(foodCategories[0].name!);
    } else {
       // Handle case where categories might be empty or first category name is null
       setState(() {
          _isLoading = false;
          _fetchErrorMessage = "No categories defined.";
       });
    }

    // Listener for PageController to update ViewModel's category index
    _pageController.addListener(() {
        int currentPage = _pageController.page?.round() ?? 0;
        // Use context.read because we are in initState/listener, not reacting to changes here
        final viewModel = context.read<HomePageViewModel>();
        if (currentPage != viewModel.currentIndex) {
           // Optionally trigger fetch directly, or let onPageChanged handle it
           // viewModel.changeCategory(currentPage); // Be careful not to cause loop
        }
    });
  }

  void _listenToSocketEvents() {
     _connectionSubscription = _socketService.onConnected.listen((isConnected) {
        if (mounted) {
           setState(() {
              _socketConnected = isConnected;
              _socketErrorMsg = isConnected ? null : (_socketErrorMsg ?? 'Disconnected'); // Clear error on connect
           });
        }
     });

     _errorSubscription = _socketService.onError.listen((error) {
         if (mounted) {
            setState(() {
               _socketErrorMsg = error;
               // Potentially set _socketConnected to false depending on error type
               if (error.contains('Connection Failed') || error.contains('Disconnected')){
                  _socketConnected = false;
               }
            });
            // Show snackbar for important errors
             if (error.contains('Failed') || error.contains('Error')){
                 ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text(error), duration: Duration(seconds: 3), backgroundColor: Colors.orange[700]),
                 );
             }
         }
     });

     _sessionStartSubscription = _socketService.onSessionStarted.listen((data) {
         if (mounted && data.containsKey('sessionId')) {
            setState(() {
               _currentSessionId = data['sessionId'];
            });
            ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Session Started: ${_currentSessionId}'), duration: Duration(seconds: 2), backgroundColor: Colors.green[600]),
            );
         }
     });

     _sessionEndSubscription = _socketService.onSessionEnded.listen((data) {
         if (mounted) {
            setState(() {
               _currentSessionId = null; // Clear session ID locally
               _cancelOrder(); // Clear the cart when session ends
            });
             String billMessage = "Session Ended.";
             if (data.containsKey('bill') && data['bill'] is Map) {
               final bill = data['bill'];
               billMessage += " Bill: ${bill['total']} DZD.";
             }
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text(billMessage), duration: Duration(seconds: 5)),
             );
            // Optionally navigate away or reset UI further
            // Consider navigating back to LandingPage or showing a "Session Ended" overlay
         }
     });
  }

  // Method to fetch menu items for a given category NAME
  Future<void> _fetchMenuItems(String categoryName) async {
    print("HomePage: Attempting to fetch items for category: $categoryName"); // Log call
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _fetchErrorMessage = null;
    });

    // --- Add this line ---
    // Immediately mark this category as the one we are now fetching.
    _currentlyFetchingCategory = categoryName;
    // --- End Add ---

    try {
      final items = await _apiService.getMenuItemsByCategory(categoryName);
      print("HomePage: Fetched ${items.length} items for $categoryName"); // Log success
      
      if (!mounted) return;

      // --- Add this check ---
      // Only update state if the result is for the category we are currently interested in.
      if (categoryName != _currentlyFetchingCategory) {
         print("HomePage: Ignoring stale fetch result for $categoryName (current: $_currentlyFetchingCategory)");
         return; // Don't update state with old data
      }
      // --- End Add ---

      setState(() {
        _displayedItems = items;
        // Update local cache only if category doesn't exist or needs refresh
        if (!_cachedItems.containsKey(categoryName)) {
          _cachedItems[categoryName] = items;
        } else {
           // Optional: Merge or replace based on your caching strategy
           _cachedItems[categoryName] = items; 
        }
        _isLoading = false;
        _fetchErrorMessage = null;
        _updateCartStatus(); // Update cart status after fetching
      });
    } catch (e) {
       print("HomePage: Error fetching items for $categoryName: $e"); // Log error
       if (!mounted) return;

       // --- Add this check (optional but good practice) ---
       // Only show error if it's for the currently targeted category
       if (categoryName != _currentlyFetchingCategory) {
            print("HomePage: Ignoring stale fetch error for $categoryName (current: $_currentlyFetchingCategory)");
            return; 
       }
       // --- End Add ---

       setState(() {
        _fetchErrorMessage = "Failed to load items. ${e.toString()}"; 
        _isLoading = false;
        _displayedItems = []; // Clear items on error
        _updateCartStatus();
      });
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error fetching items: $_fetchErrorMessage"), duration: Duration(seconds: 3))
          );
      }
    }
  }

  // --- Helper functions (updateItemState, getAllItemsInCart, etc.) remain the same ---
   void _updateItemState(MenuItem item, Function(MenuItem foundItem) updateAction) {
    // Find the item in the cache and update it
    if (_cachedItems.containsKey(item.category)) {
      var categoryList = _cachedItems[item.category]!;
      int itemIndex = categoryList.indexWhere((cachedItem) => cachedItem.id == item.id);
      
      if (itemIndex != -1) {
        updateAction(categoryList[itemIndex]);
      } else {
        // If not in cache (shouldn't happen with current flow), update the item directly
        updateAction(item);
      }
    } else {
       // If category not even in cache, update item directly
       updateAction(item);
    }
    // Update the displayed list if the modified item is currently displayed
    int displayedIndex = _displayedItems.indexWhere((dispItem) => dispItem.id == item.id);
    if (displayedIndex != -1) {
       // This ensures the UI reflects changes immediately if the item is visible
       // updateAction should have already modified the instance in _displayedItems
       // if it came from the _cachedItems reference.
    }
    _updateCartStatus(); // Recalculate cart status
  }

   List<MenuItem> _getAllItemsInCart() {
    List<MenuItem> itemsInCart = [];
    _cachedItems.values.forEach((categoryItems) {
      itemsInCart.addAll(categoryItems.where((item) => item.count > 0));
    });
    final itemIds = itemsInCart.map((item) => item.id).toSet();
    itemsInCart.retainWhere((item) => itemIds.remove(item.id)); 
    return itemsInCart;
  }

  int calculateTotalItems() {
    int total = 0;
    _cachedItems.values.forEach((categoryItems) {
      total += categoryItems.fold(0, (sum, item) => sum + item.count);
    });
    return total;
  }

  double calculateTotalAmount() {
    double total = 0.0;
     _cachedItems.values.forEach((categoryItems) {
        total += categoryItems.fold(0.0, (sum, item) => sum + item.price * item.count);
     });
     return total;
  }

  void _updateCartStatus() {
    if (mounted) {
      setState(() {
        itemSelected = calculateTotalItems() > 0;
      });
    }
  }

  void _cancelOrder() {
     if(mounted){
        setState(() {
           _cachedItems.forEach((key, itemList) {
             for (var item in itemList) {
               item.count = 0;
               item.isSelected = false;
             }
           });
            _displayedItems.forEach((item) { 
               item.count = 0;
               item.isSelected = false;
            });
           _updateCartStatus(); 
        });
     }
  }

  // --- Callbacks for ItemInfoPage --- 
  void _incrementItemFromInfo(MenuItem item) {
    if(mounted){
       setState(() {
         _updateItemState(item, (foundItem) {
           foundItem.count++;
           foundItem.isSelected = true;
         });
       });
    }
  }

  void _decrementItemFromInfo(MenuItem item) {
    if(mounted){
       setState(() {
         _updateItemState(item, (foundItem) {
           if (foundItem.count > 0) {
             foundItem.count--;
             if (foundItem.count == 0) {
               foundItem.isSelected = false;
             }
           }
         });
       });
    }
  }
  // --- End Callbacks ---

  @override
  Widget build(BuildContext context) {
    // Access the ViewModel
    // Use context.watch or Consumer where rebuilds are needed
    // Use context.read where only accessing methods/data without listening

    return Scaffold(
      key: _scaffoldKey,
      // Use Consumer for parts that need ViewModel data for build
      endDrawer: Consumer<HomePageViewModel>(
        builder: (context, viewModel, child) => Drawer(
          child: drawerCount == 1
              ? (_itemForInfoDrawer != null
                  ? ItemInfoPage(
                      menuItem: _itemForInfoDrawer!,
                      // Use ViewModel methods for callbacks
                      onIncrement: () => viewModel.incrementItem(_itemForInfoDrawer!),
                      onDecrement: () => viewModel.decrementItem(_itemForInfoDrawer!),
                    )
                  : const Center(child: Text("Error: Item data missing."))) // Added const
              : _buildCartDrawer(context, viewModel), // Extracted cart drawer build logic
         ),
      ),
      appBar: AppBar(
         actions: [
           // Use Consumer or context.watch for dynamic parts
           Consumer<HomePageViewModel>(
               builder: (context, viewModel, _) => _buildSocketStatusIndicator(viewModel)
           ),
           Consumer<HomePageViewModel>(
               builder: (context, viewModel, _) => _buildRetryConnectionButton(context, viewModel)
           ),
           const SizedBox(width: 16), // Added const
         ],
        toolbarHeight: 100,
        automaticallyImplyLeading: false,
        // Use Consumer for parts that change
        title: Consumer<HomePageViewModel>(
           builder: (context, viewModel, _) => _buildAppBarTitle(context, viewModel), // Extracted AppBar title
        ),
      ),
      body: Stack(
        children: [
          Container(
             decoration: const BoxDecoration( // Added const to potentially static decoration
               gradient: LinearGradient(
                 begin: Alignment.bottomCenter,
                 end: Alignment.topCenter,
                 colors: [ Color(0xffFFF3C4), Color(0xffFFFCF0), ],
                 stops: [0.0, 0.7],
               ),
             ),
            child: Row(
              children: [
                // Category List View - Needs to rebuild based on currentIndex
                Consumer<HomePageViewModel>(
                   builder: (context, viewModel, _) => _buildCategoryList(context, viewModel), // Extracted Category List
                ),
                // PageView for displaying items
                Expanded(
                  // Consumer needed here to react to loading/error/data changes
                  child: Consumer<HomePageViewModel>(
                     builder: (context, viewModel, _) => PageView.builder(
                        physics: const BouncingScrollPhysics(), // Added const
                        controller: _pageController,
                        itemCount: viewModel.foodCategories.length,
                        onPageChanged: (index) {
                           // Update ViewModel state when page changes via swipe
                           context.read<HomePageViewModel>().changeCategory(index);
                        },
                        itemBuilder: (context, pageIndex) {
                           // Build based on ViewModel state for the *current* index
                           if (pageIndex == viewModel.currentIndex) {
                              if (viewModel.isLoading) {
                                 return _buildLoadingIndicator();
                              }
                              if (viewModel.fetchErrorMessage != null) {
                                 return _buildErrorDisplay(context, viewModel.fetchErrorMessage!); // Pass context
                              }
                              final items = viewModel.displayedItems;
                              if (items.isEmpty) {
                                 return _buildEmptyCategoryDisplay();
                              }
                              // Render the grid - Pass viewModel or needed methods
                              return _buildItemGrid(context, viewModel, items); // Renamed from buildItemGrid
                           } else {
                              // Show simple loading for non-active pages
                              return const Center(child: CircularProgressIndicator()); // Added const
                           }
                        }
                     ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom Bar - Needs to rebuild based on cart state & session state
          Align(
             alignment: Alignment.bottomCenter,
             child: Consumer<HomePageViewModel>( // Wrap bottom bar content
                builder: (context, viewModel, _) => _buildBottomBar(context, viewModel), // Extracted Bottom Bar
             ),
           )
        ],
      ),
    );
  }

  // --- Extracted Build Methods ---

  Widget _buildAppBarTitle(BuildContext context, HomePageViewModel viewModel) {
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         Text(
           "Table ID: ${viewModel.tableId ?? 'Registering...'}",
           style: Theme.of(context)
               .textTheme
               .titleMedium!
               .copyWith(fontSize: 14, color: Colors.grey[700]),
         ),
         const SizedBox(height: 4),
         Text(
           "Session: ${viewModel.currentSessionId ?? 'Inactive'}",
           style: Theme.of(context)
               .textTheme
               .titleMedium!
               .copyWith(fontSize: 14, color: viewModel.currentSessionId != null ? Colors.blue[700] : Colors.grey[700]),
         ),
         const SizedBox(height: 10),
         Row(
           children: [
             Expanded(
               child: Text(
                 "Scroll to choose your item",
                 style: Theme.of(context)
                     .textTheme
                     .titleMedium!
                     .copyWith(fontSize: 13, color: strikeThroughColor),
                 overflow: TextOverflow.ellipsis,
               ),
             ),
           ],
         )
       ],
     );
  }

  Widget _buildCategoryList(BuildContext context, HomePageViewModel viewModel) {
      return Container(
        width: 90,
        child: ListView.builder(
            physics: const BouncingScrollPhysics(), // Added const
            itemCount: viewModel.foodCategories.length,
            itemBuilder: (context, index) {
              final category = viewModel.foodCategories[index];
              final bool isSelected = viewModel.currentIndex == index;
              return InkWell(
                onTap: () {
                  final currentViewModel = context.read<HomePageViewModel>();
                  if (category.name != null && !currentViewModel.isLoading) {
                      _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                      );
                      currentViewModel.changeCategory(index);
                  } else if(category.name == null) {
                      print("Error: Category name is null at index $index");
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Invalid category selected."))
                      );
                  }
                },
                child: Container(
                  height: 90,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: Column( // Content remains similar
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      FadedScaleAnimation(
                        child: Image.asset(
                          category.image,
                          scale: 3.5,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, size: 30),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        category.name?.toUpperCase() ?? 'ERR',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontSize: 10, color: isSelected ? Colors.white : null),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              );
            }),
      );
  }

  Widget _buildBottomBar(BuildContext context, HomePageViewModel viewModel) {
     return Container(
       alignment: Alignment.bottomCenter,
       height: 100,
       decoration: BoxDecoration(
         borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
         gradient: LinearGradient(
           begin: Alignment.bottomCenter,
           end: Alignment.topCenter,
           colors: [ Theme.of(context).primaryColor, transparentColor ], // transparentColor likely needs const
         ),
       ),
       child: Padding(
         padding: const EdgeInsets.symmetric(horizontal: 15),
         child: Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             if (viewModel.isCartSelected)
               GestureDetector(
                 onTap: () => context.read<HomePageViewModel>().cancelOrder(),
                 child: Text(
                   "Cancel Order",
                   style: Theme.of(context)
                       .textTheme
                       .bodyLarge!
                       .copyWith(fontSize: 17, color: Colors.white),
                 ),
               ),
             if (viewModel.currentSessionId != null)
                _buildEndSessionButton(context, viewModel),
             const Spacer(),
             if (viewModel.isCartSelected)
                _buildItemsInCartButton(context, viewModel),
             if (!viewModel.isCartSelected && viewModel.currentSessionId == null)
                const SizedBox.shrink(),
           ],
         ),
       ),
     );
  }

  // --- Helper Build Methods --- (Renamed and refined)

  Widget _buildLoadingIndicator() {
     return Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           FadedSlideAnimation(
             child: const Text("Loading delicious items..."),
             beginOffset: const Offset(0.0, 0.3),
             endOffset: const Offset(0, 0),
             slideCurve: Curves.linearToEaseOut,
           ),
           const SizedBox(height: 24),
           Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.only(top: 6, bottom: 100, start: 16, end: 32),
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white, // Cannot be const because of BorderRadius
                    ),
                    child: Column(
                      children: [
                        const Expanded(flex: 3, child: ColoredBox(color: Colors.white)), // Image area placeholder
                        Padding(padding: const EdgeInsets.all(8), child: Container(height: 16, color: Colors.white)), // Title placeholder
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Container(height: 16, width: 80, color: Colors.white)), // Price placeholder
                      ],
                    ),
                  );
                },
              ),
            ),
         ],
       ),
     );
  }

  Widget _buildErrorDisplay(BuildContext context, String message) {
     return Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(Icons.error_outline, size: 60, color: Colors.red[400]),
           const SizedBox(height: 16),
           Text("Error: $message", textAlign: TextAlign.center),
           const SizedBox(height: 16),
           if (message.contains("Failed to load items"))
              ElevatedButton.icon(
                 icon: const Icon(Icons.refresh),
                 label: const Text("Retry Fetch"),
                 onPressed: () {
                    final viewModel = context.read<HomePageViewModel>();
                    if (viewModel.currentCategoryName != null) {
                       viewModel.fetchMenuItems(viewModel.currentCategoryName!); // Trigger fetch
                    }
                 },
                 style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
              )
         ],
       ),
     );
  }

  Widget _buildEmptyCategoryDisplay() {
    return const Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(Icons.search_off, size: 60, color: Color(0xffbdbdbd)), // Use actual grey color value
           SizedBox(height: 16),
           Text("No items available in this category"),
         ],
       ),
     );
  }

  // Review Order Button builder - Renamed
  CustomButton _buildItemsInCartButton(BuildContext context, HomePageViewModel viewModel) {
     final itemCount = viewModel.totalItemsInCart;
    return CustomButton(
      onTap: () {
         if (itemCount > 0) {
            setState(() {
               drawerCount = 0;
            });
            _scaffoldKey.currentState!.openEndDrawer();
         } else {
             ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text("Your cart is empty."), duration: Duration(seconds: 2))
             );
         }
      },
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      title: Row(
        children: [
          Text(
            "Review Order ($itemCount)",
            style:
                Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17, color: Colors.white),
          ),
          const Icon(
            Icons.chevron_right,
            color: Colors.white,
          )
        ],
      ),
      bgColor: buttonColor,
    );
  }

  // Item Grid builder - Renamed
  Widget _buildItemGrid(BuildContext context, HomePageViewModel viewModel, List<MenuItem> itemsToDisplay) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding:
          const EdgeInsetsDirectional.only(top: 6, bottom: 100, start: 16, end: 32),
      itemCount: itemsToDisplay.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75),
      itemBuilder: (context, index) {
        // Use the new _MenuItemGridTile widget
        return _MenuItemGridTile(
          item: itemsToDisplay[index],
          // Pass callbacks or the whole viewModel if needed inside the tile
          onTap: () => context.read<HomePageViewModel>().toggleItemSelection(itemsToDisplay[index]),
          onInfoTap: () {
             setState(() {
                _itemForInfoDrawer = itemsToDisplay[index];
                drawerCount = 1;
             });
             _scaffoldKey.currentState!.openEndDrawer();
          },
          onIncrement: () => context.read<HomePageViewModel>().incrementItem(itemsToDisplay[index]),
          onDecrement: () => context.read<HomePageViewModel>().decrementItem(itemsToDisplay[index]),
        );
      },
    );
  }

  // --- Cart Drawer Logic Extraction ---

  Widget _buildCartDrawer(BuildContext context, HomePageViewModel viewModel) {
      return SafeArea(
        child: Column(
          children: [
             _buildCartHeader(context),
             Expanded(
                child: _buildCartItemList(context, viewModel),
             ),
             _buildCartFooter(context, viewModel),
          ],
        ),
      );
  }

  Widget _buildCartHeader(BuildContext context) {
    return Padding(
       padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("My Order", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text("Quick Checkout", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          ],
       ),
    );
  }

  Widget _buildCartItemList(BuildContext context, HomePageViewModel viewModel) {
    final itemsInCart = viewModel.itemsInCart;
    return ListView.builder(
       physics: const BouncingScrollPhysics(),
       padding: const EdgeInsets.symmetric(horizontal: 10),
       itemCount: itemsInCart.length,
       itemBuilder: (context, index) {
         // Use the new _CartListItem widget
         return _CartListItem(
             item: itemsInCart[index],
             onIncrement: () => context.read<HomePageViewModel>().incrementItem(itemsInCart[index]),
             onDecrement: () => context.read<HomePageViewModel>().decrementItem(itemsInCart[index]),
         );
       }
    );
  }

  Widget _buildCartFooter(BuildContext context, HomePageViewModel viewModel) {
    return Container(
       padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1, thickness: 0.5),
            Padding(
             padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),
             child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                   padding: const EdgeInsets.only(bottom: 10),
                   child: Text("Choose Ordering Method", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
                ),
                _orderingMethod(context, viewModel) // Use extracted method
              ],
            ),
           ),
            const Divider(height: 1, thickness: 0.5),
            ListTile(
              tileColor: Theme.of(context).colorScheme.surface,
              title: Text("Total Amount", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade700)),
              trailing: Text(
               viewModel.totalAmountCart.toStringAsFixed(2) + ' DZD',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blueGrey.shade900, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            FadedScaleAnimation(
             child: CustomButton(
                onTap: () => _placeOrder(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
                margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 60),
                title: Text("Place Order", style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                bgColor: buttonColor,
                borderRadius: 8,
              ),
           ),
          ],
        ),
      );
  }


  // orderingMethod - Renamed
  Widget _orderingMethod(BuildContext context, HomePageViewModel viewModel) {
    return Row(
       mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(child: _buildOrderingButton(context, viewModel, 0, "Take Away", "assets/ic_takeaway.png")),
          const SizedBox(width: 10),
          Expanded(child: _buildOrderingButton(context, viewModel, 1, "Dine In", "assets/ic_dine in.png")),
        ],
    );
  }

  // _buildOrderingButton - Renamed
  Widget _buildOrderingButton(BuildContext context, HomePageViewModel viewModel, int index, String title, String imagePath) {
      bool selected = viewModel.orderingIndex == index;
      return GestureDetector(
         onTap: () => viewModel.setOrderingIndex(index),
         child: Container(
             padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
             height: 65,
             decoration: BoxDecoration(
                color: selected ? const Color(0xffFFEEC8) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                   color: selected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                   width: selected ? 1.5 : 1.0
                ),
             ),
             child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Image.asset(imagePath, height: 24),
                   const SizedBox(width: 8),
                   Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                ],
             ),
         ),
      );
   }

  // Helper method for placing order to handle dialogs and call ViewModel
  Future<void> _placeOrder(BuildContext context) async {
     // Use context.read to access the view model for placing the order
     final viewModel = context.read<HomePageViewModel>();

     // Show loading indicator
     showDialog(
         context: context,
         barrierDismissible: false,
         builder: (BuildContext context) => Dialog( /* ... Loading Dialog ... */
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text("Placing Order..."),
                ],
              ),
            ),
         ),
     );

     try {
         final orderResponse = await viewModel.placeOrder();
         Navigator.pop(context); // Close loading dialog

         String orderIdString = orderResponse['order']?['id']?.toString() ?? '';
         int? orderNum = int.tryParse(orderIdString.length > 4 ? orderIdString.substring(orderIdString.length - 4) : orderIdString);
         double totalAmount = viewModel.totalAmountCart; // Get total from VM

         // Navigate to order placed screen
         Navigator.push(
             context,
             MaterialPageRoute(
                 builder: (context) => OrderPlaced(
                     orderId: orderIdString,
                     orderNumber: orderNum,
                     totalAmount: totalAmount,
                 ),
             ),
         );

         // Reset cart using ViewModel method
         viewModel.cancelOrder();

     } catch (e) {
         Navigator.pop(context); // Close loading dialog on error
         print("Error placing order: $e");
         ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Error placing order: ${e.toString()}"), backgroundColor: Colors.red[600])
         );
     }
  }

  // Helper method for ending session to handle dialog and call ViewModel
  void _endSession(BuildContext context) {
     // Use context.read to access the view model
     final viewModel = context.read<HomePageViewModel>();

     // Check conditions using ViewModel state before showing dialog
     if (viewModel.currentSessionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No active session to end.")));
        return;
     }
     if (!viewModel.socketConnected) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Not connected to server. Cannot end session.")));
        return;
     }

     showDialog(
         context: context,
         builder: (BuildContext context) => AlertDialog( // Confirmation Dialog
             title: Text("End Session?"),
             content: Text("Are you sure you want to end the current session? This will generate the bill."),
             actions: <Widget>[
                 TextButton(
                     child: Text("Cancel"),
                     onPressed: () => Navigator.of(context).pop(),
                 ),
                 TextButton(
                     child: Text("End Session", style: TextStyle(color: Colors.red)),
                     onPressed: () {
                         Navigator.of(context).pop(); // Close dialog
                         print("HomePage: Calling viewModel.endCurrentSession()");
                         viewModel.endCurrentSession(); // Call VM method
                     },
                 ),
             ],
         ),
     );
  }

  // Button to end session - Renamed
  Widget _buildEndSessionButton(BuildContext context, HomePageViewModel viewModel) {
    return viewModel.currentSessionId != null
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: CustomButton(
             title: const Text("End Session", style: TextStyle(color: Colors.white, fontSize: 17)),
             bgColor: Colors.orange[700],
             onTap: () => _endSession(context), // Call helper method
             padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
             margin: const EdgeInsets.symmetric(vertical: 10),
             borderRadius: 8,
          ),
        )
      : const SizedBox.shrink();
  }

  // --- Socket Status Indicators and Helpers --- (Keep as is, already extracted)
  Widget _buildSocketStatusIndicator(HomePageViewModel viewModel) {
    IconData icon;
    Color color;
    String text;

    if (viewModel.isConnecting) { // Use VM getter
        icon = Icons.wifi_tethering;
        color = Colors.blue;
        text = 'Connecting...';
    } else if (viewModel.socketConnected) { // Use VM getter
      icon = Icons.wifi;
      color = Colors.green;
      text = 'Online';
    } else {
      icon = Icons.wifi_off;
      color = Colors.red;
      text = 'Offline';
    }

    return Row( // Structure remains same
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildRetryConnectionButton(BuildContext context, HomePageViewModel viewModel) {
    return (!viewModel.socketConnected && !viewModel.isConnecting) // Use VM getters
      ? IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry Connection',
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Attempting to reconnect...'), duration: Duration(seconds: 2))
            );
            // Call VM method - Use context.read or viewModel directly
            await viewModel.manualReconnect();
          },
        )
       : const SizedBox.shrink();
  }

  @override
  void dispose() {
    // Cancel all stream subscriptions
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _sessionStartSubscription?.cancel();
    _sessionEndSubscription?.cancel();
    _pageController.dispose();
    // Note: SocketService itself is a singleton and might not be disposed here.
    super.dispose();
  }
}

// --- New Extracted Widgets ---

class _MenuItemGridTile extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _MenuItemGridTile({
    required this.item,
    required this.onTap,
    required this.onInfoTap,
    required this.onIncrement,
    required this.onDecrement,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double gridItemCacheWidth = 300;
    const double gridItemCacheHeight = 225;

    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).scaffoldBackgroundColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 35,
            child: GestureDetector(
              onTap: onTap,
              child: Stack(
                children: [
                  Container(
                       decoration: const BoxDecoration(
                       borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: ClipRRect(
                       borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                       child: FadedScaleAnimation(
                          child: item.image != null && item.image!.isNotEmpty
                            ? Image.network(
                                item.image!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                cacheWidth: gridItemCacheWidth.round(),
                                cacheHeight: gridItemCacheHeight.round(),
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: Colors.grey[200],
                                    alignment: Alignment.center,
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null,
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                   return Container(color: Colors.grey[200], child: Icon(Icons.broken_image, color: Colors.grey[500], size: 40,));
                                },
                              )
                            : Container(color: Colors.grey[200], child: Icon(Icons.image_not_supported, color: Colors.grey[500], size: 40,)),
                       ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                        icon: Icon(Icons.info_outline, color: Colors.grey.shade400, size: 18),
                        onPressed: onInfoTap,
                      ),
                  ),
                  if (item.count > 0)
                      Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                      onTap: onDecrement,
                                      child: const Icon(Icons.remove, color: Colors.white, size: 24)),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    child: Text(
                                      item.count.toString(),
                                      style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                      onTap: onIncrement,
                                      child: const Icon(Icons.add, color: Colors.white, size: 24)),
                                ],
                              ),
                            ),
                          ),
                       )
                ],
              ),
            ),
          ),
          const Spacer(flex: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              item.name,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const Spacer(flex: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Image.asset(
                  item.isVeg ? 'assets/ic_veg.png' : 'assets/ic_nonveg.png',
                  scale: 2.8,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.price.toStringAsFixed(2) + ' DZD',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 5),
        ],
      ),
    );
  }
}

class _CartListItem extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _CartListItem({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
      const double cartItemCacheWidth = 60;
      const double cartItemCacheHeight = 60;

      return Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.image != null && item.image!.isNotEmpty
                ? Image.network(
                    item.image!,
                    width: cartItemCacheWidth,
                    height: cartItemCacheHeight,
                    fit: BoxFit.cover,
                    cacheWidth: cartItemCacheWidth.round(),
                    cacheHeight: cartItemCacheHeight.round(),
                    errorBuilder: (context, error, stackTrace) => Container(width: cartItemCacheWidth, height: cartItemCacheHeight, color: Colors.grey[200], child: const Icon(Icons.broken_image, size: 30)),
                    loadingBuilder: (context, child, prog) => prog == null ? child : Container(width: cartItemCacheWidth, height: cartItemCacheHeight, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))
                )
                : Container(width: cartItemCacheWidth, height: cartItemCacheHeight, color: Colors.grey[200], child: const Icon(Icons.image_not_supported, size: 30)),
            ),
            title: Row(
               children: [
                 Expanded(child: Text(item.name, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
                 Image.asset(item.isVeg ? 'assets/ic_veg.png' : 'assets/ic_nonveg.png', height: 14),
               ],
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300, width: 1)
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: onDecrement,
                        child: Icon(Icons.remove, color: Theme.of(context).primaryColor, size: 18)
                      ),
                      const SizedBox(width: 10),
                      Text(item.count.toString(), style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: onIncrement,
                        child: Icon(Icons.add, color: Theme.of(context).primaryColor, size: 18)
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(item.price.toStringAsFixed(2) + ' DZD', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))
              ],
            ),
          ),
          const Divider(thickness: 0.5),
        ],
      );
  }
}
