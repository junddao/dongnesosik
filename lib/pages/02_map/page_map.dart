import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dongnesosik/global/enums/view_state.dart';
import 'package:dongnesosik/global/model/model_shared_preferences.dart';
import 'package:dongnesosik/global/model/pin/model_request_create_pin_reply.dart';
import 'package:dongnesosik/global/model/pin/model_response_get_pin.dart';
import 'package:dongnesosik/global/model/pin/model_response_get_pin_reply.dart';
import 'package:dongnesosik/global/model/singleton_user.dart';
import 'package:dongnesosik/global/model/user/model_user_info.dart';
import 'package:dongnesosik/global/provider/location_provider.dart';
import 'package:dongnesosik/global/provider/user_provider.dart';
import 'package:dongnesosik/global/service/login_service.dart';
import 'package:dongnesosik/global/style/constants.dart';
import 'package:dongnesosik/global/style/dscolors.dart';
import 'package:dongnesosik/global/style/dstextstyles.dart';
import 'package:dongnesosik/global/util/date_converter.dart';
import 'package:dongnesosik/global/util/range_by_zoom.dart';
import 'package:dongnesosik/pages/03_post/page_post.dart';
import 'package:dongnesosik/pages/components/ds_button.dart';
import 'package:dongnesosik/pages/components/ds_photo_view.dart';
import 'package:dongnesosik/pages/components/ds_two_button_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

class PageMap extends StatefulWidget {
  const PageMap({Key? key, this.pinId}) : super(key: key);

  final int? pinId;

  @override
  _PageMapState createState() => _PageMapState();
}

class _PageMapState extends State<PageMap> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Marker> _markers = [];
  List<Marker> _temporaryMaker = [];
  Completer<GoogleMapController> _controller = Completer();

  BitmapDescriptor? customIcon;
  Timer? _timer;
  int? range = 1000;

  List<String> imageUrls = [test_image_url, test_image_url, test_image_url];
  TextEditingController _tecMessage = TextEditingController();
  final PanelController panelController = new PanelController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // panelController.hide(); //초기에 slideUpPanel 숨기고 시작
    // setCustomMarker();
    Future.microtask(() async {
      await getLocation();

      Future.delayed(Duration(milliseconds: 500), () {
        if (panelController.isPanelOpen) {
          panelController.close();
        }
        if (widget.pinId != null) {
          panelController.open();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();

    _scrollController.dispose();
    super.dispose();
  }

  Future<BitmapDescriptor> createCustomMarkerBitmap(
      String? profileImage, String title) async {
    // final Size size = Size(150, 150);
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Radius radius = Radius.circular(70);

    final Paint tagPaint = Paint()..color = Color(0xFF5963d9);

    // Add tag text
    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
        text: title.length < 18 ? title : title.substring(0, 16) + '..',
        style: DSTextStyles.mediaum32White);

    textPainter.layout();

    // Add tag circle
    canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
              0.0, 0.0, textPainter.width + 40, textPainter.height + 20),
          topLeft: radius,
          topRight: radius,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        tagPaint);

    textPainter.paint(canvas, Offset(20, 10));

    // Convert canvas to image
    final ui.Image markerAsImage = await pictureRecorder.endRecording().toImage(
        textPainter.width.toInt() + 80, textPainter.height.toInt() + 40);

    // Convert image to bytes
    final ByteData? byteData =
        await markerAsImage.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(uint8List);
  }

  Future<ui.Image> getImageFromAsset(String imagePath) async {
    final byteData = await rootBundle.load(imagePath);

    Uint8List imageBytes = Uint8List.view(byteData.buffer);
    final Completer<ui.Image> completer = new Completer();

    ui.decodeImageFromList(imageBytes, (ui.Image img) {
      return completer.complete(img);
    });

    return completer.future;
  }

  Future<ui.Image> getImageFromNetwork(String url) async {
    Uint8List imageBytes = (await NetworkAssetBundle(Uri.parse(url)).load(url))
        .buffer
        .asUint8List();

    // Uint8List imageBytes = Uint8List.view(byteData.buffer);
    final Completer<ui.Image> completer = new Completer();

    ui.decodeImageFromList(imageBytes, (ui.Image img) {
      return completer.complete(img);
    });

    return completer.future;
  }

  Future<void> getLocation() async {
    if (context.read<LocationProvider>().lastLocation != null) {
      moveCameraToLastLocation();
      return;
    }
    if (context.read<LocationProvider>().myLocation != null) {
      moveCameraToMyLocation();
      return;
    }

    // bool _serviceEnabled;
    // PermissionStatus _permissionGranted;

    // _serviceEnabled = await location.serviceEnabled();
    // if (!_serviceEnabled) {
    //   _serviceEnabled = await location.requestService();
    //   if (!_serviceEnabled) {
    //     return Future.error('Location services are disabled.');
    //   }
    // }

    // _permissionGranted = await location.hasPermission();
    // if (_permissionGranted == PermissionStatus.denied) {
    //   _permissionGranted = await location.requestPermission();
    //   if (_permissionGranted != PermissionStatus.granted) {
    //     return Future.error('Location services are disabled.');
    //   }
    // }

    // LocationData locationData = await location.getLocation();
    // print(locationData.latitude!);
    // print(locationData.longitude!);
    // LatLng latlng = LatLng(locationData.latitude!, locationData.longitude!);

    // context.read<LocationProvider>().setMyLocation(latlng);
    // context.read<LocationProvider>().setLastLocation(latlng);
    // moveCameraToMyLocation();
  }

  void moveCameraToMyLocation() {
    var provider = context.read<LocationProvider>();
    _controller.future.then((value) {
      value.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          bearing: 0,
          target: LatLng(
              provider.myLocation!.latitude, provider.myLocation!.longitude),
          zoom: 15,
        ),
      ));
    });
  }

  void moveCameraToLastLocation() {
    var provider = context.read<LocationProvider>();
    _controller.future.then((value) {
      value.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          bearing: 0,
          target: LatLng(provider.lastLocation!.latitude,
              provider.lastLocation!.longitude),
          zoom: 15,
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        floatingActionButton: _floatingActionButton(),
        appBar: _appBar(),
        body: _body(),
        drawer: _drawer(),
        extendBodyBehindAppBar: true,
        drawerEnableOpenDragGesture: true,
        resizeToAvoidBottomInset: false,
        floatingActionButtonLocation: FloatingActionButtonLocation.miniEndTop,
        // resizeToAvoidBottomInset: false,

        // floatingActionButton: FloatingActionButton(
        //   child: Icon(Icons.add, color: DSColors.white),

        //   // child: Text('글쓰기', style: DSTextStyle.bold12Black),
        //   backgroundColor: DSColors.tomato,
        //   onPressed: () async {
        //     Navigator.of(context).pushNamed('PagePostCreate');
        //   },
        // ),
        // floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (panelController.isPanelOpen) {
      panelController.close();
      return false;
    } else {
      return true;
    }
  }

  Widget _floatingActionButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 100.0),
      child: FloatingActionButton(
        mini: true,
        child: Icon(Icons.my_location_outlined),
        onPressed: () {
          moveCameraToMyLocation();
        },
      ),
    );
  }

  AppBar _appBar() {
    var provider = context.watch<LocationProvider>();
    return AppBar(
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: Icon(Icons.menu),
        onPressed: () {
          _scaffoldKey.currentState!.openDrawer();
        },
      ),
      title: Text(
          provider.placemarks.isEmpty
              ? ''
              : provider.placemarks[0].subLocality!,
          style: DSTextStyles.bold18Black),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: () {
            context.read<LocationProvider>().setMyPostLocation(null);
            Navigator.of(context).pushNamed('PagePostCreate');
          },
          child: Text('새글쓰기', style: DSTextStyles.bold14Tomato),
        ),
      ],
    );
  }

  Widget _drawer() {
    return Drawer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ListView(
            shrinkWrap: true,
            padding: EdgeInsets.only(left: 10),
            children: <Widget>[
              // drawer header
              _drawerHeader(),

              // my history

              ListTile(
                leading: Icon(Ionicons.document_text_outline),
                title: Text(
                  '내글보기',
                  style: DSTextStyles.bold14Black,
                ),
                onTap: () {
                  Navigator.of(context).pushNamed('PageMyPost');
                },
              ),
              ListTile(
                leading: Icon(Ionicons.documents_outline),
                title: Text(
                  '인기글보기',
                  style: DSTextStyles.bold14Black,
                ),
                onTap: () {
                  Navigator.of(context).pushNamed('PagePopularPost');
                },
              ),
              ListTile(
                leading: Icon(Ionicons.help),
                title: Text(
                  '사용법보기',
                  style: DSTextStyles.bold14Black,
                ),
                onTap: () {
                  Navigator.of(context).pushNamed('PageIntroSlider');
                },
              ),
            ],
          ),
          ListView(
            shrinkWrap: true,
            padding: EdgeInsets.only(left: 10),
            children: [
              SingletonUser.singletonUser.userData.email == null ||
                      SingletonUser.singletonUser.userData.email!.isEmpty
                  ? ListTile(
                      leading: Icon(Ionicons.share_social_outline),
                      title: Text(
                        '계정 연결',
                        style: DSTextStyles.bold14Black,
                      ),
                      onTap: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                            'PageLogin', (route) => false);
                        // Navigator.of(context)
                        //     .pushNamedAndRemoveUntil('PageRoot', (route) => false);
                      },
                    )
                  : SizedBox.shrink(),
              SingletonUser.singletonUser.userData.email == null ||
                      SingletonUser.singletonUser.userData.email!.isEmpty
                  ? SizedBox.shrink()
                  : ListTile(
                      leading: Icon(Ionicons.log_out_outline),
                      title: Text(
                        '로그아웃',
                        style: DSTextStyles.bold14Black,
                      ),
                      onTap: () {
                        logout();
                      },
                    ),
              SizedBox(height: 50),
            ],
          ),
        ],
      ),
    );
    // Disable opening the drawer with a swipe gesture.
  }

  Widget _body() {
    return Consumer(builder: (_, LocationProvider value, child) {
      if (value.lastLocation == null || value.responseGetPinDatas == null) {
        return Center(child: CircularProgressIndicator());
      } else {
        LatLng _lastLocation = value.lastLocation!;

        return SafeArea(
          top: false,
          child: SlidingUpPanel(
            controller: panelController,
            backdropEnabled: true,
            minHeight: kDefaultCollapseHeight,
            maxHeight: SizeConfig.screenHeight * 0.8,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            // renderPanelSheet: false,
            collapsed: _floatingCollapsed(),
            panel: _floatingPanel(),
            onPanelClosed: () {
              FocusScope.of(context).unfocus();
            },

            body: Stack(
              children: [
                GoogleMap(
                  onMapCreated: (controller) async {
                    await _onMapCreated(controller, _lastLocation);
                  },
                  initialCameraPosition: CameraPosition(
                    target: _lastLocation,
                    zoom: 15,
                  ),

                  markers: [..._markers, ..._temporaryMaker].toSet(),
                  rotateGesturesEnabled: false,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,

                  padding: EdgeInsets.only(bottom: 130, right: 0),
                  // mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,

                  onTap: (point) {
                    _handleTap(point);
                  },
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  Widget _floatingCollapsed() {
    var provider = context.read<LocationProvider>();

    return provider.selectedPinData == null
        ? postSummaryWidget()
        : postContentsBottomSheet(provider.responseGetPinDatas!);
  }

  Widget postSummaryWidget() {
    return _newsInfoWidget();
  }

  Widget _floatingPanel() {
    var provider = context.read<LocationProvider>();

    if (provider.selectedPinData == null) {
      return postListWidget();
    } else {
      return SafeArea(
        bottom: true,
        top: false,
        child: viewPostContents(),
      );
    }
  }

  Widget postListWidget() {
    var responseGetPinData =
        context.watch<LocationProvider>().responseGetPinDatas;
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 10),
          buildDragHandle(),
          Container(
              height: 90,
              padding: EdgeInsets.all(kDefaultPadding),
              child: Center(
                  child: Text('동네 게시글', style: DSTextStyles.bold18Black))),
          Divider(),
          ListView.separated(
              padding: EdgeInsets.only(top: 0),
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return _listItem(index, responseGetPinData!);
              },
              separatorBuilder: (context, index) {
                return Divider();
              },
              itemCount: responseGetPinData!.length),
        ],
      ),
    );
  }

  Widget _listItem(int index, List<ResponseGetPinData> responseGetPinData) {
    return InkWell(
      onTap: () {
        context.read<LocationProvider>().selectedPinData =
            responseGetPinData[index];

        context
            .read<LocationProvider>()
            .getPinReply(responseGetPinData[index].pin!.id!);
        LatLng location = LatLng(responseGetPinData[index].pin!.lat!,
            responseGetPinData[index].pin!.lng!);
        context.read<LocationProvider>().setLastLocation(location);
        setState(() {
          moveCameraToLastLocation();
        });
        // panelController.close();
      },
      child: ListTile(
        leading: Container(
          height: 60,
          width: 60,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: responseGetPinData[index].pin!.images == null ||
                    responseGetPinData[index].pin!.images!.isEmpty
                ? SvgPicture.asset(
                    'assets/images/void.svg',
                    height: 60,
                    width: 60,
                    fit: BoxFit.cover,
                  )
                : CachedNetworkImage(
                    imageUrl: responseGetPinData[index].pin!.images!.first,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) {
                      return SvgPicture.asset(
                        'assets/images/void.svg',
                        height: 60,
                        width: 60,
                        fit: BoxFit.cover,
                      );
                    },
                  ),
          ),
        ),
        title: Text(responseGetPinData[index].pin!.title!,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          responseGetPinData[index].pin!.body!,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _drawerHeader() {
    return InkWell(
      onTap: () {
        Navigator.of(context).pushNamed('PageUserSetting');
      },
      child: Container(
        height: 200,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  height: 80,
                  width: 80,
                  child: ClipOval(
                    child: SingletonUser.singletonUser.userData.profileImage ==
                                null ||
                            SingletonUser.singletonUser.userData.profileImage ==
                                ''
                        ? SvgPicture.asset(
                            'assets/images/person.svg',
                            fit: BoxFit.cover,
                            height: 80,
                            width: 80,
                          )
                        : CachedNetworkImage(
                            imageUrl: SingletonUser
                                .singletonUser.userData.profileImage!,
                            fit: BoxFit.cover,
                            height: 80,
                            width: 80,
                          ),
                  ),
                ),
                SizedBox(width: 20),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(SingletonUser.singletonUser.userData.name!,
                        style: DSTextStyles.bold16Black),
                    Text('반갑습니다.', style: DSTextStyles.regular12WarmGrey),
                  ],
                ),
              ],
            ),
            Icon(Icons.arrow_forward_ios),
          ],
        ),
      ),
    );
  }

  Future<void> _onMapCreated(
      GoogleMapController controller, LatLng location) async {
    _markers.clear();
    var provider = context.read<LocationProvider>();

    print('onMapCreate');
    print(location.toString());

    _controller.complete(controller);

    provider.getAddress(location);
  }

  void _onCameraIdle() async {
    // _markers.clear();

    var provider = context.read<LocationProvider>();
    var userProvider = context.read<UserProvider>();

    await provider.getPinInRagne(provider.lastLocation!.latitude,
        provider.lastLocation!.longitude, range);
    provider.responseGetPinDatas!.forEach((element) async {
      customIcon = await createCustomMarkerBitmap(
          element.profileImage, element.pin!.title!);
      addCustomMarker(element.pin!.id!,
          LatLng(element.pin!.lat!, element.pin!.lng!), element);
    });
    if (provider.selectedPinData == null) {
      return;
    }
    double lat =
        DataConvert.roundDouble(provider.selectedPinData!.pin!.lat!, 6);
    double lng =
        DataConvert.roundDouble(provider.selectedPinData!.pin!.lng!, 6);
    LatLng selectedLocation = LatLng(lat, lng);
    double lastLat =
        DataConvert.roundDouble(provider.lastLocation!.latitude, 6);
    double lastLng =
        DataConvert.roundDouble(provider.lastLocation!.longitude, 6);
    LatLng lastLocation = LatLng(lastLat, lastLng);
    if (selectedLocation != lastLocation) {
      provider.selectedPinData = null;
    }
    print(selectedLocation);
    print(lastLocation);

    print("Idle");
    // var provider = context.read<LocationProvider>();
    // await provider.getPinInRagne(provider.lastLocation!.latitude,
    //     provider.lastLocation!.longitude, 1000);
  }

  void _onCameraMove(CameraPosition position) {
    var provider = context.read<LocationProvider>();

    provider.setLastLocation(position.target);
    print("move");
    print(position.zoom.toString());
    range = RangeByZoom.getRangeByZooom(position.zoom);
  }

  void addCustomMarker(int id, LatLng latLng, ResponseGetPinData? data) async {
    final marker = Marker(
      markerId: MarkerId(id.toString()),
      position: latLng,
      icon: customIcon!,
      onTap: () async {
        print('marker onTap()');
        var responseGetPinDatas = context
            .read<LocationProvider>()
            .responseGetPinDatas!
            .where((element) {
          return element.pin!.id == id;
        }).toList();

        context.read<LocationProvider>().selectedPinData =
            responseGetPinDatas.first;
        context.read<LocationProvider>().getPinReply(id);

        panelController.open();
        print('marker onTaped()');
      },
    );
    _markers.add(marker);
    context.read<LocationProvider>().setStateIdle();
  }

  void addMarker(int id, LatLng latLng) async {
    final marker = Marker(
        markerId: MarkerId(id.toString()),
        position: latLng,
        onTap: () async {
          print('marker onTap()');
          context.read<LocationProvider>().getPinReply(id);

          // context.read<LocationProvider>().setSelectedId(id);

          // showModalBottomSheet(
          //   context: context,
          //   isScrollControlled: true,
          //   builder: (context) {
          //     return Padding(
          //       padding: EdgeInsets.only(
          //           bottom: MediaQuery.of(context).viewInsets.bottom),
          //       child: buildBottomSheet(context, id),
          //     );
          //   },
          // );
        });
    _markers.add(marker);
  }

  _handleTap(LatLng point) {
    var provider = context.read<LocationProvider>();
    double lat = DataConvert.roundDouble(point.latitude, 6);
    double lng = DataConvert.roundDouble(point.longitude, 6);
    LatLng location = LatLng(lat, lng);

    print('handelTap');
    provider.setMyPostLocation(location);
    provider.getAddress(location);

    _temporaryMaker.clear();
    addTemporaryMarker(0, location);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return buildSelectLocationBottomSheet(context);
      },
    ).then((value) {
      if (value != true) {
        // 취소하면 postLocation 초기화 필요.
        context.read<LocationProvider>().setMyPostLocation(null);
      }
      _temporaryMaker.clear();
    });
  }

  Widget buildSelectLocationBottomSheet(BuildContext context) {
    var provider = context.watch<LocationProvider>();
    // String? address = provider.placemarks[0].name!;
    String? address = '';
    if (Platform.isAndroid) {
      address = provider.placemarks[0].street;
    } else {
      address = provider.placemarks[0].name!;
    }

    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          color: DSColors.white),
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(address!, style: DSTextStyles.bold14Black),
            SizedBox(
              height: 10,
            ),
            Divider(),
            DSButton(
              text: '여기에 새글을 쓰겠어요!',
              width: SizeConfig.screenWidth,
              press: () {
                Navigator.of(context)
                    .popAndPushNamed('PagePostCreate', result: true);
              },
            ),
            DSButton(
              text: '다음에 쓸께요.',
              width: SizeConfig.screenWidth,
              type: ButtonType.transparent,
              press: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void addTemporaryMarker(int id, LatLng latLng) {
    final marker = Marker(
      markerId: MarkerId(id.toString()),
      position: latLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      // icon: customIcon!,
    );
    _temporaryMaker.add(marker);
  }

  Widget _newsInfoWidget() {
    var provider = context.read<LocationProvider>();

    return provider.responseGetPinDatas!.length == 0
        ? Container(
            decoration: BoxDecoration(
              color: DSColors.white,
            ),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [Text('주변에 글이 없어요. 첫 글을 작성해보세요. 😀')],
            ),
          )
        : InkWell(
            onTap: () {
              panelController.open();
            },
            child: Container(
              decoration: BoxDecoration(
                color: DSColors.white,
              ),
              padding: EdgeInsets.symmetric(
                  horizontal: kDefaultHorizontalPadding, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                            text: ' ${provider.responseGetPinDatas!.length}개',
                            style: DSTextStyles.bold14Black),
                        TextSpan(
                            text: '의 글이 검색되었어요.',
                            style: DSTextStyles.regular12WarmGrey),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  getAnimatedTitle(provider),
                ],
              ),
            ),
          );
  }

  Widget postContentsBottomSheet(List<ResponseGetPinData> responseGetPinDatas) {
    return Consumer<LocationProvider>(builder: (_, data, __) {
      if (data.state == ViewState.Busy) {
        return Center(
          child: CircularProgressIndicator(),
        );
      }
      return InkWell(
        onTap: () {
          panelController.open();
        },
        child: Container(
          height: kDefaultCollapseHeight,
          decoration: BoxDecoration(
            color: DSColors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: kDefaultHorizontalPadding,
                vertical: kDefaultVerticalPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 60,
                    width: 60,
                    child: data.selectedPinData!.pin!.images == null ||
                            data.selectedPinData!.pin!.images!.isEmpty
                        ? SvgPicture.asset(
                            'assets/images/void.svg',
                            fit: BoxFit.cover,
                          )
                        : CachedNetworkImage(
                            imageUrl: data.selectedPinData!.pin!.images!.first,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) {
                              return SvgPicture.asset(
                                'assets/images/void.svg',
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.selectedPinData!.pin!.title!,
                        style: DSTextStyles.bold18Black,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 10),
                      Text(
                        data.selectedPinData!.pin!.body!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget viewPostContents() {
    return Consumer<LocationProvider>(builder: (_, data, __) {
      if (data.state == ViewState.Busy) {
        return Center(
          child: CircularProgressIndicator(),
        );
      }
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            height: SizeConfig.screenHeight * 0.8,
            child: Column(
              // mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(height: 10),
                buildDragHandle(),
                Container(
                  height: 90,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () {
                            int userId = context
                                .read<LocationProvider>()
                                .selectedPinData!
                                .userId!;
                            context.read<UserProvider>().getUser(userId);
                            Navigator.of(context)
                                .pushNamed('PageOtherUser', arguments: userId);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              data.selectedPinData!.profileImage == null ||
                                      data.selectedPinData!.profileImage!
                                          .isEmpty
                                  ? SvgPicture.asset(
                                      'assets/images/person.svg',
                                      fit: BoxFit.cover,
                                      height: 40,
                                      width: 40,
                                    )
                                  : CircleAvatar(
                                      radius: 20.0,
                                      backgroundImage:
                                          CachedNetworkImageProvider(
                                        data.selectedPinData!.profileImage!,
                                      ),
                                    ),
                              SizedBox(width: 4),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                        text: '${data.selectedPinData!.name!}',
                                        style: DSTextStyles.bold18Black),
                                    TextSpan(
                                        text: ' 님의 글',
                                        style: DSTextStyles.bold12Black),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                  text: DataConvert.toGapTimewithNow(
                                      data.selectedPinData!.createAt!),
                                  style: DSTextStyles.regular14WarmGrey),
                              TextSpan(
                                  text:
                                      '  (${DataConvert.toLocalDateWithMinute(data.selectedPinData!.createAt!)})',
                                  style: DSTextStyles.regular10WarmGrey),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    // reverse: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: DSPhotoView(
                              iamgeUrls:
                                  data.selectedPinData!.pin!.images ?? [],
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: kDefaultHorizontalPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data.selectedPinData!.pin!.title!,
                                  style: DSTextStyles.bold16Black),
                              SizedBox(height: 20),
                              Text(data.selectedPinData!.pin!.body!),
                              SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      data.selectedPinData!.liked == false
                                          ? InkWell(
                                              onTap: () {
                                                context
                                                    .read<LocationProvider>()
                                                    .pinLikeToId(data
                                                        .selectedPinData!
                                                        .pin!
                                                        .id!)
                                                    .then((value) {
                                                  context
                                                      .read<LocationProvider>()
                                                      .getPinById(data
                                                          .selectedPinData!
                                                          .pin!
                                                          .id!);
                                                });
                                              },
                                              child: Icon(
                                                Icons.favorite_border_outlined,
                                              ),
                                            )
                                          : Icon(
                                              Icons.favorite,
                                              color: DSColors.tomato,
                                            ),
                                      SizedBox(width: 8),
                                      Text(
                                          '${data.selectedPinData!.pin!.likeCount ?? 0}',
                                          style: DSTextStyles.regular10Grey06),
                                      SizedBox(width: 18),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      showCupertinoModalPopup<void>(
                                        context: context,
                                        builder: (BuildContext context) =>
                                            CupertinoActionSheet(
                                                title: const Text('신고 / 차단'),
                                                message: const Text(
                                                    '신고, 차단한 글은\n 지도상에 표시되지 않습니다.'),
                                                actions: <
                                                    CupertinoActionSheetAction>[
                                                  CupertinoActionSheetAction(
                                                    child: const Text(
                                                        '불건전 컨텐츠 신고하기'),
                                                    onPressed: () async {
                                                      var provider = context.read<
                                                          LocationProvider>();
                                                      await provider
                                                          .pinHateToId(data
                                                              .selectedPinData!
                                                              .pin!
                                                              .id!)
                                                          .then((value) {
                                                        // provider.getPinById(data
                                                        //     .selectedPinData!.pin!.id!);
                                                        provider.selectedPinData =
                                                            null;
                                                      });

                                                      await provider
                                                          .getPinInRagne(
                                                              provider
                                                                  .lastLocation!
                                                                  .latitude,
                                                              provider
                                                                  .lastLocation!
                                                                  .longitude,
                                                              range);
                                                      Navigator.of(context)
                                                          .pushNamed(
                                                              'PageConfirm',
                                                              arguments: [
                                                            '불건전 컨텐츠 신고하기',
                                                            '신고가 정상적으로 접수되었습니다.',
                                                            '해당 글은 더이상 노출되지 않습니다.'
                                                          ]);
                                                    },
                                                  ),
                                                  CupertinoActionSheetAction(
                                                    child:
                                                        const Text('글쓴이 차단하기'),
                                                    onPressed: () async {
                                                      var provider = context.read<
                                                          LocationProvider>();
                                                      await provider
                                                          .pinHateToId(data
                                                              .selectedPinData!
                                                              .pin!
                                                              .id!)
                                                          .then((value) {
                                                        // provider.getPinById(data
                                                        //     .selectedPinData!.pin!.id!);
                                                        provider.selectedPinData =
                                                            null;
                                                      });

                                                      await provider
                                                          .getPinInRagne(
                                                              provider
                                                                  .lastLocation!
                                                                  .latitude,
                                                              provider
                                                                  .lastLocation!
                                                                  .longitude,
                                                              range);
                                                      Navigator.of(context)
                                                          .pushNamed(
                                                              'PageConfirm',
                                                              arguments: [
                                                            '차단하기',
                                                            '불건전 컨테츠 작성자로 판단되어 해당 사용자를 차단하였습니다.',
                                                            '해당 사용자의 글은 숨김처리 됩니다.'
                                                          ]);
                                                    },
                                                  ),
                                                ],
                                                cancelButton:
                                                    CupertinoActionSheetAction(
                                                  child: const Text('취소'),
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                  },
                                                )),
                                      );
                                    },
                                    child: Icon(Icons.more_horiz,
                                        color: DSColors.tomato),
                                  )
                                ],
                              ),
                              SizedBox(height: 10),
                              data.selectedPinData!.hated == true
                                  ? Text('2시간 내 운영자 검토 후 필요시 삭제 예정입니다.',
                                      style: DSTextStyles.regular10PinkishGrey)
                                  : SizedBox.shrink(),
                              SizedBox(height: 10),
                              Divider(),
                              _buildReviewList(data),
                            ],
                          ),
                        ),

                        // const SizedBox(height: 90),
                      ],
                    ),
                  ),
                ),
                _buildMessageComposer(data),
              ],
            ),
          ),
        ),
      );
    });
  }

  _scrollToEnd() async {
    _scrollController.animateTo(_scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  Widget buildDragHandle() {
    return Center(
      child: Container(
          width: 30,
          height: 5,
          decoration: BoxDecoration(
            color: DSColors.warm_grey,
          )),
    );
  }

  void onClosePress() async {
    Navigator.of(context).pop();
  }

  getAnimatedTitle(LocationProvider provider) {
    return SizedBox(
      // width: 250.0,
      child: DefaultTextStyle(
        style: DSTextStyles.regular12Black,
        overflow: TextOverflow.ellipsis,
        child: AnimatedTextKit(
          repeatForever: true,
          isRepeatingAnimation: true,
          animatedTexts: [
            for (ResponseGetPinData data in provider.responseGetPinDatas!)
              buildText(data),
          ],
          onTap: () {
            print("Tap Event");
          },
        ),
      ),
    );
    // return Row(
    //   children: [
    //     const SizedBox(width: 0.0, height: 50.0),
    //     DefaultTextStyle(
    //       style: DSTextStyles.regular12Black,
    //       overflow: TextOverflow.ellipsis,
    //       child: AnimatedTextKit(
    //         repeatForever: true,
    //         isRepeatingAnimation: true,
    //         animatedTexts: [
    //           for (ResponseGetPinData data in provider.responseGetPinDatas!)
    //             buildText(data),
    //         ],
    //       ),
    //     ),
    //   ],
    // );
  }

  buildText(ResponseGetPinData data) {
    return FadeAnimatedText(
      data.pin!.title!,
      duration: Duration(seconds: 3),
    );
    // return RotateAnimatedText(data.pin!.title!);
  }

  Widget _buildMessageComposer(LocationProvider data) {
    return Container(
      // height: 50,
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              margin: EdgeInsets.all(0),
              padding: EdgeInsets.all(0),
              decoration: BoxDecoration(
                border: Border.all(color: Color(0xFFEFEFEF)),
                borderRadius: BorderRadius.circular(21),
                color: Color(0xFFF8F8F8),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _tecMessage,
                      onChanged: (value) {},
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      decoration: InputDecoration.collapsed(
                        hintText: '메세지를 입력하세요',
                      ),
                    ),
                  ),
                  InkWell(
                    child: Container(
                      child: Icon(Icons.send),
                      padding: EdgeInsets.all(4),
                    ),
                    onTap: () {
                      createReply();
                      FocusScope.of(context).unfocus();
                      WidgetsBinding.instance!
                          .addPostFrameCallback((_) => _scrollToEnd());
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void createReply() {
    var provider = context.read<LocationProvider>();
    if (_tecMessage.text.isEmpty) {
      return;
    }

    // 대댓글 처리용
    if (provider.selectedReplyData != null) {}

    ModelRequestCreatePinReply modelRequestCreatePinReply =
        ModelRequestCreatePinReply(
      pinId: provider.selectedPinData!.pin!.id,
      body: _tecMessage.text,
    );
    _tecMessage.text = '';
    provider.createReply(modelRequestCreatePinReply).then((value) {
      context
          .read<LocationProvider>()
          .getPinReply(provider.selectedPinData!.pin!.id!);
    });
  }

  Widget _buildReviewList(LocationProvider provider) {
    return provider.responseGetPinReplyData!.length == 0
        ? emptyReview()
        : ListView.separated(
            physics: NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.only(top: 0),
            itemCount: provider.responseGetPinReplyData!.length,
            itemBuilder: (context, index) {
              var data = provider.responseGetPinReplyData![index];

              return data.userId != SingletonUser.singletonUser.userData.id
                  ? getOhterUserReply(data)
                  : getMyReply(provider.responseGetPinReplyData!, index);
            },
            separatorBuilder: (context, index) => Divider(),
          );
  }

  Widget emptyReview() {
    return Container(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('첫 리뷰를 작성해 보세요. 🙂'),
        ],
      ),
    );
  }

  Widget getOhterUserReply(ModelResponseGetPinReplyData data) {
    return InkWell(
      onTap: () {
        // context.read<LocationProvider>().setReplyTarget(data);
        // _tecMessage.text = '@${data.name} ';

        int userId = data.userId!;
        context.read<UserProvider>().getUser(userId);
        Navigator.of(context).pushNamed('PageOtherUser', arguments: userId);
      },
      child: Container(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(data.name!, style: DSTextStyles.bold12Black),
                    SizedBox(width: 16),
                    Text(DataConvert.toLocalDateWithSeconds(data.createAt!),
                        style: DSTextStyles.regular10WarmGrey),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  data.reply!.body!,
                  style: DSTextStyles.regular12Black,
                ),
                SizedBox(height: 8),
              ],
            ),
            SingletonUser.singletonUser.userData.isAdmin == true
                ? IconButton(
                    onPressed: () {
                      context
                          .read<LocationProvider>()
                          .deleteReply(data.reply!.id!);
                      setState(() {});
                    },
                    icon: Icon(Icons.delete),
                  )
                : SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget getMyReply(List<ModelResponseGetPinReplyData> datas, int index) {
    ModelResponseGetPinReplyData data = datas[index];
    return Slidable(
      key: const ValueKey(0),
      endActionPane: ActionPane(
        motion: ScrollMotion(),
        children: [
          SlidableAction(
            // An action can be bigger than the others.
            onPressed: (slidableContext) {
              deleteReply(slidableContext, datas[index]);
            },
            flex: 2,
            backgroundColor: Color(0xFFFE4A49),
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: DSColors.tomato_10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(data.name!, style: DSTextStyles.bold12Black),
                SizedBox(width: 16),
                Text(DataConvert.toLocalDateWithSeconds(data.createAt!),
                    style: DSTextStyles.regular10WarmGrey),
              ],
            ),
            SizedBox(height: 8),
            Text(
              data.reply!.body!,
              style: DSTextStyles.regular12Black,
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void deleteReply(
      BuildContext slidableContext, ModelResponseGetPinReplyData reply) async {
    var result = await DSDialog.showTwoButtonDialog(
        context: context,
        title: '댓글 삭제',
        subTitle: '정말 삭제하시겠습니까?',
        btn1Text: '아니요,',
        btn2Text: '네,');
    if (result == true) {
      context
          .read<LocationProvider>()
          .deleteReply(reply.reply!.id!)
          .then((value) {
        context.read<LocationProvider>().getPinReply(
            context.read<LocationProvider>().selectedPinData!.pin!.id!);
      });
    }
  }

  void logout() {
    LoginService().signOut().then((value) {
      if (value is String) {
        // fail
        print(value);
        Scaffold.of(context).showSnackBar(SnackBar(content: Text(value)));
      } else {
        // success

        // ModelSharedPreferences.removeToken();
        ModelSharedPreferences.removeAll();

        SingletonUser.singletonUser.userData = ModelUserInfo();

        Navigator.of(context)
            .pushNamedAndRemoveUntil('PageLogin', (route) => false);
      }
    });
  }
}
