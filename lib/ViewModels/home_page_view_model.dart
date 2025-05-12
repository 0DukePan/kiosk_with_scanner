import 'dart:async';
import 'package:flutter/material.dart';
import '../Models/menu_item.dart';
import '../Services/api_service.dart';
import '../Services/socket_service.dart';
import '../Pages/home_page.dart'; // For ItemCategory

class HomePageViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final SocketService _socketService;

  HomePageViewModel(this._apiService, this._socketService) {
    // Initialize state from services
    _socketConnected = _socketService.isConnected;
    _currentSessionId = _socketService.sessionId;
    _tableId = _socketService.tableId; // Store initial tableId

    // Listen to socket events
    _listenToSocketEvents();

    // Fetch initial category
    if (foodCategories.isNotEmpty && foodCategories[0].name != null) {
      fetchMenuItems(foodCategories[0].name!);
    } else {
      _isLoading = false;
      _fetchErrorMessage = "No categories defined.";
      notifyListeners();
    }
  }

  // --- State Variables ---
  Map<String, List<MenuItem>> _cachedItems = {};
  bool _isLoading = true;
  String? _fetchErrorMessage;
  int _orderingIndex = 0;
  int _currentIndex = 0; // Category index
  String? _currentlyFetchingCategory;

  // Socket/Session related state
  bool _socketConnected = false;
  String? _socketErrorMsg;
  String? _currentSessionId;
  String? _tableId; // Keep track of table ID
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _sessionStartSubscription;
  StreamSubscription? _sessionEndSubscription;
  StreamSubscription? _tableRegisteredSubscription; // To update tableId

  // Hardcoded categories (could be fetched too) - Keep accessible
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

  // --- Getters for UI ---
  bool get isLoading => _isLoading;
  String? get fetchErrorMessage => _fetchErrorMessage;
  int get orderingIndex => _orderingIndex;
  int get currentIndex => _currentIndex;
  bool get socketConnected => _socketConnected;
  bool get isConnecting => _socketService.isConnecting; // Delegate to service
  String? get socketErrorMsg => _socketErrorMsg;
  String? get currentSessionId => _currentSessionId;
  String? get tableId => _tableId ?? _socketService.tableId; // Use service value if local is null
  String? get currentCategoryName => _currentIndex < foodCategories.length ? foodCategories[_currentIndex].name : null;

  // Derived State Getters
  List<MenuItem> get displayedItems {
    final categoryName = currentCategoryName;
    if (categoryName == null) return [];
    // Return a copy to prevent modifying the cached list directly elsewhere by mistake
    return List<MenuItem>.from(_cachedItems[categoryName] ?? []);
  }

  List<MenuItem> get itemsInCart {
    List<MenuItem> items = [];
    _cachedItems.values.forEach((categoryItems) {
      items.addAll(categoryItems.where((item) => item.count > 0));
    });
    // Ensure uniqueness (optional, but good practice)
     final itemIds = items.map((item) => item.id).toSet();
     items.retainWhere((item) => itemIds.remove(item.id));
    return items;
  }

  int get totalItemsInCart => itemsInCart.fold(0, (sum, item) => sum + item.count);

  double get totalAmountCart => itemsInCart.fold(0.0, (sum, item) => sum + (item.price * item.count));

  bool get isCartSelected => totalItemsInCart > 0;


  // --- Public Methods (Actions) ---

  void changeCategory(int index) {
    if (index != _currentIndex && index >= 0 && index < foodCategories.length) { // Added bounds check
       _currentIndex = index;
       final categoryName = foodCategories[index].name;
       if (categoryName != null) {
           fetchMenuItems(categoryName); // Fetch initiates loading state etc.
       } else {
           _isLoading = false;
           _fetchErrorMessage = "Selected category is invalid.";
           // Ensure we handle the case where a category might not exist in cache yet
           // _cachedItems.removeWhere((key, value) => key == null); // Not needed if categoryName is null
           notifyListeners();
       }
       // No need to notifyListeners here, fetchMenuItems will do it
    }
  }

  void setOrderingIndex(int index) {
    if (index != _orderingIndex) {
      _orderingIndex = index;
      notifyListeners();
    }
  }

  Future<void> fetchMenuItems(String categoryName) async {
    _isLoading = true;
    _fetchErrorMessage = null;
    _currentlyFetchingCategory = categoryName;
    notifyListeners(); // Notify UI about loading start

    try {
      final items = await _apiService.getMenuItemsByCategory(categoryName);
      if (categoryName == _currentlyFetchingCategory && _cachedItems.containsKey(categoryName)) { // Check if fetch is still relevant and cache exists
         // Preserve counts only for items already in the *specific* category cache before replacing
         final Map<String, int> previousCounts = {
            for (var item in _cachedItems[categoryName]!) item.id: item.count
         };
         for (var fetchedItem in items) {
            fetchedItem.count = previousCounts[fetchedItem.id] ?? 0; // Default to 0 if not found
            fetchedItem.isSelected = fetchedItem.count > 0;
         }
      } else if (categoryName == _currentlyFetchingCategory) {
          // If category wasn't cached before, ensure counts are 0
           for (var fetchedItem in items) {
               fetchedItem.count = 0;
               fetchedItem.isSelected = false;
           }
      }


      // Only update state if the fetch is still relevant
      if (categoryName == _currentlyFetchingCategory) {
        _cachedItems[categoryName] = items; // Replace or add the category data
        _isLoading = false;
        _fetchErrorMessage = null;
      }
    } catch (e) {
      if (categoryName == _currentlyFetchingCategory) { // Check if fetch is still relevant
        _fetchErrorMessage = "Failed to load items. ${e.toString()}";
        _isLoading = false;
        _cachedItems.remove(categoryName); // Clear potentially partial/bad data
      }
    } finally {
       // Only notify if the fetch was for the category we are currently interested in
       if (categoryName == _currentlyFetchingCategory) {
           notifyListeners(); // Notify UI about loading end/error
       }
    }
  }

  void updateItemCount(MenuItem item, int change) {
      if (_cachedItems.containsKey(item.category)) {
          var categoryList = _cachedItems[item.category]!;
          int itemIndex = categoryList.indexWhere((i) => i.id == item.id);
          if (itemIndex != -1) {
              int newCount = categoryList[itemIndex].count + change;
              if (newCount >= 0) { // Ensure count doesn't go below 0
                 categoryList[itemIndex].count = newCount;
                 categoryList[itemIndex].isSelected = newCount > 0;
                 notifyListeners(); // Update UI
              }
          }
      } else {
          print("Warning: Attempted to update item count for category '${item.category}' not found in cache.");
      }
  }

   void incrementItem(MenuItem item) {
       updateItemCount(item, 1);
   }

   void decrementItem(MenuItem item) {
       updateItemCount(item, -1);
   }

   // Toggles selection AND updates count accordingly
   void toggleItemSelection(MenuItem item) {
        if (_cachedItems.containsKey(item.category)) {
            var categoryList = _cachedItems[item.category]!;
            int itemIndex = categoryList.indexWhere((i) => i.id == item.id);
            if (itemIndex != -1) {
                bool wasSelected = categoryList[itemIndex].isSelected;
                // Toggle selection state FIRST
                categoryList[itemIndex].isSelected = !wasSelected;

                // Adjust count based on NEW selection state
                if (categoryList[itemIndex].isSelected) {
                   // If it's now selected, ensure count is at least 1
                   if (categoryList[itemIndex].count == 0) {
                      categoryList[itemIndex].count = 1;
                   }
                } else {
                   // If it's now deselected, reset count to 0
                   categoryList[itemIndex].count = 0;
                }
                notifyListeners();
            }
        } else {
           print("Warning: Attempted to toggle selection for category '${item.category}' not found in cache.");
        }
   }


  void cancelOrder() {
    _cachedItems.forEach((key, itemList) {
      for (var item in itemList) {
        item.count = 0;
        item.isSelected = false;
      }
    });
    notifyListeners();
  }

  // Returns the API response or throws an exception on failure
  Future<Map<String, dynamic>> placeOrder() async {
      final items = itemsInCart; // Use getter
      final String orderType = _orderingIndex == 0 ? 'Take Away' : 'Dine In';
      final String? currentTableId = tableId; // Use getter which checks service

      if (items.isEmpty) {
          throw Exception("Cart is empty.");
      }
      if (currentTableId == null) {
          throw Exception("Table not registered.");
      }
      if (!_socketConnected) { // Use local state synced from service
           throw Exception("Not connected to server.");
      }

      // Try-catch might be better handled in the UI calling this method
      return await _apiService.createOrder(
          items: items,
          orderType: orderType,
          tableId: currentTableId,
      );
      // Caller (UI) should call cancelOrder() after successful navigation
  }

   void endCurrentSession() {
       if (_currentSessionId == null) {
           _socketErrorMsg = "No active session to end."; // Update local error state
           notifyListeners();
           // Optionally throw an exception if the UI should handle it differently
           // throw Exception("No active session to end.");
           return;
       }
       if (!_socketConnected) {
           _socketErrorMsg = "Not connected to server."; // Update local error state
           notifyListeners();
           // throw Exception("Not connected to server.");
           return;
       }
       // Table ID check might not be strictly necessary for ending session via socket
       // if (_tableId == null) {
       //      _socketErrorMsg = "Table ID missing.";
       //      notifyListeners();
       //      return;
       // }
       _socketService.endCurrentSession(); // Let SocketService handle the emit
       // State (_currentSessionId) will be updated via the 'session_ended' listener
   }

   Future<void> manualReconnect() async {
      // Add state to indicate reconnection attempt if desired
      _socketErrorMsg = "Attempting manual reconnect...";
      notifyListeners();
      await _socketService.manualReconnect();
      // State updates (connected, error) will come via listeners
   }


  // --- Socket Event Listeners ---
  void _listenToSocketEvents() {
    _connectionSubscription = _socketService.onConnected.listen((isConnected) {
      _socketConnected = isConnected;
      _socketErrorMsg = isConnected ? null : (_socketErrorMsg ?? 'Disconnected');
       // Potentially update tableId here too if connection implies registration occurs
      _tableId = _socketService.tableId;
      notifyListeners();
    });

    _errorSubscription = _socketService.onError.listen((error) {
      _socketErrorMsg = error;
      if (error.contains('Connection Failed') || error.contains('Disconnected')) {
        _socketConnected = false;
      }
      notifyListeners();
    });

    _sessionStartSubscription = _socketService.onSessionStarted.listen((data) {
      if (data.containsKey('sessionId')) {
        _currentSessionId = data['sessionId'];
        notifyListeners();
         // Optionally clear errors on successful session start
         _socketErrorMsg = null;
      }
    });

    _sessionEndSubscription = _socketService.onSessionEnded.listen((data) {
      _currentSessionId = null; // Clear session ID
      cancelOrder(); // Clear cart (already calls notifyListeners)
      // Optionally add message from `data` to state if needed
       String billMessage = "Session Ended.";
       if (data.containsKey('bill') && data['bill'] is Map) {
          final bill = data['bill'];
          billMessage += " Bill: ${bill['total']} DZD.";
       }
       _socketErrorMsg = billMessage; // Display bill info briefly as an "error" message
      // No need to call notifyListeners() again if cancelOrder() did it.
    });

    // Listen for table registration confirmation to update local tableId
    _tableRegisteredSubscription = _socketService.onTableRegistered.listen((data) {
         // Get the latest tableId from the service after registration acknowledged
         final serviceTableId = _socketService.tableId;
         if (serviceTableId != _tableId) {
             _tableId = serviceTableId;
             notifyListeners();
         }
    });
  }

  // --- Cleanup ---
  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _sessionStartSubscription?.cancel();
    _sessionEndSubscription?.cancel();
    _tableRegisteredSubscription?.cancel();
    super.dispose();
  }
} 