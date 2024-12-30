import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:responsi2/Service/auth_service.dart';
import 'package:responsi2/View/login_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:responsi2/View/pending_requests_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final AuthService _authService = AuthService();

  int totalWastePoints = 0;
  int pendingRequests = 0;
  int completedRequests = 0;

  // Tambahkan properties untuk Google Maps
  final Set<Marker> _markers = {};
  GoogleMapController? _mapController;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadWastePoints();
    _getCurrentLocation();
  }

  Future<void> _loadDashboardData() async {
    try {
      final response = await http.get(
        Uri.parse('${_authService.baseUrl}/dashboard'),
        headers: {
          'Authorization': 'Bearer ${_authService.token}',
          'Content-Type': 'application/json',
        },
      );

      print('API URL: ${_authService.baseUrl}/dashboard');
      print('Token: ${_authService.token}');
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];
        
        setState(() {
          totalWastePoints = data['total_waste_points'] ?? 0;
          pendingRequests = data['pending_requests'] ?? 0;
          completedRequests = data['completed_requests'] ?? 0;
        });
      } else {
        print('Error status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading dashboard data: $e');
    }
  }

  Future<void> _loadWastePoints() async {
    try {
      final response = await http.get(
        Uri.parse('${_authService.baseUrl}/waste-points'),
        headers: {
          'Authorization': 'Bearer ${_authService.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _markers.clear();
          for (var point in data['waste_points']) {
            _markers.add(
              Marker(
                markerId: MarkerId(point['id'].toString()),
                position: LatLng(
                  double.parse(point['latitude'].toString()),
                  double.parse(point['longitude'].toString()),
                ),
                infoWindow: InfoWindow(
                  title: point['name'],
                  snippet: point['type'] == 'public_bin'
                      ? 'Tempat Sampah Umum'
                      : 'Titik Pengumpulan',
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      print('Error loading waste points: $e');
    }
  }

  Future<void> _showAddWastePointDialog(BuildContext context) async {
    final TextEditingController nameController = TextEditingController();
    String selectedType = 'public_bin';
    LatLng? selectedLocation;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Titik Sampah'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Lokasi',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedType,
              items: const [
                DropdownMenuItem(
                  value: 'public_bin',
                  child: Text('Tempat Sampah Umum'),
                ),
                DropdownMenuItem(
                  value: 'collection_point',
                  child: Text('Titik Pengumpulan'),
                ),
              ],
              onChanged: (value) {
                selectedType = value!;
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final LatLng? pickedLocation = await _showLocationPicker(context);
                if (pickedLocation != null && nameController.text.isNotEmpty) {
                  try {
                    final response = await http.post(
                      Uri.parse('${_authService.baseUrl}/waste-points'),
                      headers: {
                        'Authorization': 'Bearer ${_authService.token}',
                        'Content-Type': 'application/json',
                      },
                      body: jsonEncode({
                        'name': nameController.text,
                        'type': selectedType,
                        'latitude': pickedLocation.latitude.toString(),
                        'longitude': pickedLocation.longitude.toString(),
                      }),
                    );

                    if (response.statusCode == 201) {
                      _loadWastePoints(); // Reload markers
                      _loadDashboardData(); // Reload dashboard data
                    }
                  } catch (e) {
                    print('Error adding waste point: $e');
                  }
                }
              },
              child: const Text('Pilih Lokasi di Peta'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  Future<LatLng?> _showLocationPicker(BuildContext context) async {
    LatLng? pickedLocation;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-6.200000, 106.816666), // Jakarta center
              zoom: 12,
            ),
            markers: _markers,
            onTap: (LatLng location) {
              pickedLocation = location;
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );

    return pickedLocation;
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude),
              15,
            ),
          );
        }
      });
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        title: const Text(
          'Waste Management Admin',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              _authService.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentPosition != null
                          ? LatLng(_currentPosition!.latitude,
                              _currentPosition!.longitude)
                          : const LatLng(-6.200000, 106.816666),
                      zoom: 15,
                    ),
                    markers: _markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      if (_currentPosition != null) {
                        controller.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            LatLng(_currentPosition!.latitude,
                                _currentPosition!.longitude),
                            15,
                          ),
                        );
                      }
                    },
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          'Peta Lokasi Titik Sampah',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildDashboardCard(
                    icon: Icons.location_on,
                    title: 'Titik Sampah',
                    value: totalWastePoints.toString(),
                    color: Colors.green,
                  ),
                  InkWell(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PendingRequestsScreen(),
                        ),
                      );

                      if (result == true) {
                        // Refresh halaman AdminScreen
                        setState(() {
                          // Jika ada state yang perlu diperbarui
                        });
                      }
                    },
                    child: _buildDashboardCard(
                      icon: Icons.pending_actions,
                      title: 'Permintaan Pending',
                      value: pendingRequests.toString(),
                      color: Colors.orange,
                    ),
                  ),
                  _buildDashboardCard(
                    icon: Icons.check_circle,
                    title: 'Selesai Diproses',
                    value: completedRequests.toString(),
                    color: Colors.blue,
                  ),
                  InkWell(
                    onTap: () => _showAddWastePointDialog(context),
                    child: _buildDashboardCard(
                      icon: Icons.add_location,
                      title: 'Tambah Titik',
                      value: 'Tap',
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              color.withOpacity(0.1),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
