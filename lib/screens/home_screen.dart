import 'package:flutter/material.dart';
import 'package:image_detection_new/screens/gallery_screen.dart';
import 'package:image_detection_new/screens/live_camera_screen.dart';
import 'package:image_detection_new/screens/quick_capture_screen.dart';
import 'package:image_detection_new/widgets/custom_appbar.dart';
import 'package:image_detection_new/widgets/custom_gredient_button.dart';
import 'package:image_detection_new/widgets/hero_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(preferredSize: Size.fromHeight(60), child: CustomAppbar(title: 'Image Detector App',)),


      body: Container(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            SizedBox(
              height: 30,
            ),

            HeroHeader(),

            SizedBox(
              height: 30,
            ),
            
            Text('Choose the method from the following...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20),
            ),


            SizedBox(
              height: 100,
            ),

            CustomGradientButton(
              colors: const  [Color(0xFF0EA5E9), Color(0xFF4F46E5), Color(0xFF8B5CF6)], // Gallery
              icon: Icons.collections_outlined,
              label: 'Gallery',
              onTap: (){
                goScreen(GalleryScreen());
              },
            ),

            SizedBox(
              height: 15,

            ),
            CustomGradientButton(
              colors: const  [Color(0xFF0EA5E9), Color(0xFF4F46E5), Color(0xFF8B5CF6)], // Clear
              icon: Icons.camera,
              label: 'Quick Capture',
              onTap: (){
                goScreen(QuickCaptureScreen());
              },
            ),
            SizedBox(
              height: 15,
            ),
            CustomGradientButton(
              colors: const  [Color(0xFF0EA5E9), Color(0xFF4F46E5), Color(0xFF8B5CF6)], // Clear
              icon: Icons.camera_alt,
              label: 'Live Camera',
              onTap: (){
                goScreen(LiveCameraScreen());
              },
            ),


          ],
        ),
      ),
    );
  }

goScreen(screen){
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => screen),
  );
}


}





