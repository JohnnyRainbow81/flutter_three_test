import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three3d/math/index.dart';
import 'package:three_dart/three3d/renderers/webgl/index.dart';
import 'package:three_dart/three_dart.dart' as THREE;
import 'dart:math' as math;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remembry Demo',
      theme: ThemeData(
        fontFamily: "Unica",
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(fileName: "webgl_camera"),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String fileName;

  const MyHomePage({required this.fileName, Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late FlutterGlPlugin flutterGLplugin;
  THREE.WebGLRenderer? webGLrenderer;

  int? fboId;
  late double width;
  late double height;

  Size? screenSize;

  late THREE.Scene scene;
  late THREE.Camera cameraStatic;
  late THREE.Mesh sphere;

  //late THREE.Points donutPoints;
  late THREE.Mesh donut;
  late THREE.Points pPoints;
  late THREE.Camera cameraPerspective;

  late THREE.Camera activeCamera;
  late THREE.CameraHelper activeHelper;
  THREE.Vector3? cameraPositionOld;

  late THREE.CameraHelper cameraOrthoHelper;
  late THREE.CameraHelper cameraPerspectiveHelper;

  late THREE.Texture alphaTexture;

  THREE.Vector3 mousePos = THREE.Vector3(0, 0, 0);

  //Texts

  List<String> randomTextList = [];

//Shader Example
  late THREE.Points particleSystem;
  int particles = 100000;

  int frustumSize = 600;

  double dpr = 1.0;

  num aspect = 1.0;

  var AMOUNT = 4;

  bool verbose = false;
  bool disposed = false;

  late THREE.WebGLRenderTarget webGLrenderTarget;

  dynamic sourceTexture;

  double scroll = 0;

  initAll(BuildContext context) {
    debugPrint("initAll()");

    if (screenSize != null) {
      return;
    }

    final mqd = MediaQuery.of(context);

    screenSize = mqd.size;
    dpr = mqd.devicePixelRatio;

    initPlatformState();
  }

  Future<void> initPlatformState() async {
    debugPrint("initPlatformState()");

    width = screenSize!.width;
    height = screenSize!.height;

    flutterGLplugin = FlutterGlPlugin();

    Map<String, dynamic> _options = {
      "antialias": true,
      "alpha": false,
      "width": width.toInt(),
      "height": height.toInt(),
      "dpr": dpr
    };

    await flutterGLplugin.initialize(options: _options);

//Hier wird nur 1x (!!!) setState() gecallt in der gesamten Anwendung!!
    setState(() {});

    // TODO web wait dom ok!!!
    Future.delayed(const Duration(milliseconds: 100), () async {
      await flutterGLplugin.prepareContext();

      final loader = THREE.TextureLoader(null);
      alphaTexture = await loader.loadAsync(
          "https://raw.githubusercontent.com/Kuntal-Das/textures/main/sp2.png",
          null);

      initRenderer();
      initPage();
    });
  }

  initRenderer() {
    debugPrint("initRenderer()");
    Map<String, dynamic> _options = {
      "width": width,
      "height": height,
      "gl": flutterGLplugin.gl,
      "antialias": true,
      "canvas": flutterGLplugin.element
    };
    webGLrenderer = THREE.WebGLRenderer(_options);
    webGLrenderer!.setPixelRatio(dpr);
    webGLrenderer!.setSize(width, height, false);
    webGLrenderer!.shadowMap.enabled = false;
    webGLrenderer!.autoClear = false;

// if Native..?
//in der if-clause wird trotzdem mit dem webRenderer hantiert. Hmmm...
    if (!kIsWeb) {
      var pars = THREE.WebGLRenderTargetOptions({
        "minFilter": THREE.LinearFilter,
        "magFilter": THREE.LinearFilter,
        "format": THREE.RGBAFormat,
        "samples": 4
      });
      webGLrenderTarget = THREE.WebGLRenderTarget(
          (width * dpr).toInt(), (height * dpr).toInt(), pars);
      webGLrenderer!.setRenderTarget(webGLrenderTarget);

      sourceTexture =
          webGLrenderer!.getRenderTargetGLTexture(webGLrenderTarget);
    }
  }

  initPage() {
    debugPrint("initPage()");

    aspect = width / height;

    scene = THREE.Scene();

    //

    cameraStatic = THREE.PerspectiveCamera(50, 0.5 * aspect, 1, 10000);
    cameraStatic.position.z = 2500;

    cameraPerspective =
        THREE.PerspectiveCamera(50, /* 0.5 * */ aspect, 1, 10000);

    cameraPerspectiveHelper = THREE.CameraHelper(cameraPerspective);
    scene.add(cameraPerspectiveHelper);

    //

    activeCamera = cameraPerspective;
    activeHelper = cameraPerspectiveHelper;

    // counteract different front orientation of cameras vs rig
//    cameraPerspective.rotation.y = THREE.Math.PI;

    scene.add(cameraPerspective);

    //
    //weiße kugel
    final sphereMaterial = THREE.LineBasicMaterial();
    sphereMaterial.color = THREE.Color(1, 1, 1);
    sphereMaterial.visible = false;

    sphere = THREE.Mesh(THREE.SphereGeometry(100, 16, 8),
        sphereMaterial /* THREE.MeshBasicMaterial({"color": 0xffffff, "wireframe": true}) */);

    scene.add(sphere);

//Gefüllter Torus
    final donutGeometry = THREE.TorusGeometry(50, 20, 16, 18).toNonIndexed();

    final donutMat = THREE.MeshBasicMaterial()
      ..color = THREE.Color(1, 0, 1)
      ..wireframe = true
      ..visible = false;

    donut = THREE.Mesh(donutGeometry, donutMat)..position.x = 0;

    sphere.add(donut);

    final donutPointsGeom = fillWithPoints(donutGeometry, 1000);

    final donutPointsMat = THREE.PointsMaterial()
      ..color = THREE.Color(0.8, 0.9, 1)
      ..size = 10 // THREE.MathUtils.randFloat(1, 20)
      ..map = alphaTexture
      ..alphaMap = alphaTexture
      ..vertexShader = vertexShader
      ..fragmentShader = fragmentShader
      ..transparent = true
      ..blending = THREE.CustomBlending
      ..blendEquation = THREE.AddEquation
      ..blendSrc = THREE.SrcAlphaFactor
      ..alphaToCoverage = true
      ..blendDst = THREE.OneMinusSrcAlphaFactor;

    final donutPoints = THREE.Points(donutPointsGeom, donutPointsMat);

    donut.add(donutPoints);

    //Punkte Exp
    final pPointsGeo = THREE.SphereGeometry(50, 16, 10);
    final pPointsMat = THREE.ShaderMaterial()
      ..vertexShader = vertexShader
      ..fragmentShader = fragmentShader
      ..uniforms = {
        "pointSize": {"type": "float", "value": 15.0},
        "pointsTexture": {"value": alphaTexture},
      }
      ..transparent = true;

    pPoints = THREE.Points(donutPointsGeom, pPointsMat);

    sphere.add(pPoints);

    //Sterne
    var starsGeometry = THREE.BufferGeometry();
    List<double> vertices = [];

    for (var i = 0; i < 10000; i++) {
      //s.u., durch die "3" wird nach x,y,z differenziert
      vertices.add(THREE.MathUtils.randFloatSpread(2000)); // x
      vertices.add(THREE.MathUtils.randFloatSpread(2000)); // y
      vertices.add(THREE.MathUtils.randFloatSpread(2000)); // z
    }

    starsGeometry.setAttribute('position',
        THREE.Float32BufferAttribute(Float32Array.fromList(vertices), 3));

    var starsMaterial = THREE.PointsMaterial()
      ..map = alphaTexture
      ..size = 5
      ..transparent = true
      ..blending = THREE.CustomBlending
      ..blendEquation = THREE.AddEquation
      ..blendSrc = THREE.SrcAlphaFactor
      ..alphaToCoverage = true
      ..blendDst = THREE.OneMinusSrcAlphaFactor
      ..lights = true;

    var stars = THREE.Points(starsGeometry, starsMaterial);

    scene.add(stars);

    animate();
  }

  animate() {
    if (!mounted || disposed) {
      return;
    }

    render();

//Sehr interessant! Hier wird per Recursion animiert! Merke: Es braucht kein setState()!
    Future.delayed(const Duration(milliseconds: 16), () {
      animate();
    });
  }

  render() {
    //ACHTUNG! Wird 60x / Sekunde aufgerufen!!
    int tStart = DateTime.now().millisecondsSinceEpoch;

//Wird benutzt um die Animation anzutreiben
    var driver = DateTime.now().millisecondsSinceEpoch * 0.0001;

    sphere.position.x = 700 * THREE.Math.cos(driver);
    sphere.position.z = 700 * THREE.Math.sin(driver);
    sphere.position.y = 700 * THREE.Math.sin(driver);

    //TorusPoints

    double distToCamera = cameraPerspective.position.distanceTo(donut.position);

//grüne kugel rotiert um weiße kugel
    sphere.children[0].position.x = 150 * THREE.Math.cos(2 * driver);
    sphere.children[0].position.z = 150 * THREE.Math.sin(2 * driver);

    cameraPerspective.position.z += scroll * 10;
    debugPrint("cameraPos.z: ${cameraPerspective.position.z}");

    cameraPerspective.position.x += mousePos.x;
    cameraPerspective.position.y += mousePos.y;
    //debugPrint(mousePos.dx.toString());

    cameraPerspective.lookAt(sphere.position);

    //reset
    scroll = 0;

    cameraPerspective.updateProjectionMatrix();

    webGLrenderer!.clear();

    activeHelper.visible = false;

    webGLrenderer!.setViewport(0, 0, width /*  / 2 */, height);
    webGLrenderer!.setClearColor(THREE.Color(0.0, 0.0, 0.1));
    webGLrenderer!.render(scene, activeCamera);

    activeHelper.visible = true;

    int tEnd = DateTime.now().millisecondsSinceEpoch;

    if (verbose) {
      print("render cost: ${tEnd - tStart} ");
      print(webGLrenderer!.info.memory);
      print(webGLrenderer!.info.render);
    }

    flutterGLplugin.gl.flush();

    // var pixels = _gl.readCurrentPixels(0, 0, 10, 10);
    // print(" --------------pixels............. ");
    // print(pixels);

    if (verbose) print(" render: sourceTexture: $sourceTexture ");

    if (!kIsWeb) {
      flutterGLplugin.updateTexture(sourceTexture);
    }
  }

  @override
  void dispose() {
    print(" dispose ............. ");

    disposed = true;
    flutterGLplugin.dispose();

    super.dispose();
  }

  void generateList() {
    randomTextList = List<String>.generate(100,
        (index) => "Das ist nur ein Blindtext $index");
  }

  @override
  Widget build(BuildContext context) {
    generateList();
    return Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          initAll(context);
          return SingleChildScrollView(
              child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                      width: width,
                      height: height,
                      child: Builder(builder: (BuildContext context) {
                        if (kIsWeb) {
                          return flutterGLplugin.isInitialized
                              ? HtmlElementView(
                                  viewType:
                                      flutterGLplugin.textureId!.toString())
                              : Container();
                        } else {
                          return flutterGLplugin.isInitialized
                              ? Texture(textureId: flutterGLplugin.textureId!)
                              : Container();
                        }
                      })),
                  SizedBox(
                    width: width,
                    height: height,
                    child: Center(
                      // We need Listener because it's the only way to get mouse scrolling events
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent) {
                            scroll =  event.scrollDelta.dy * 0.01;
                          }
                        },
                        // We need MouseRegion because "onExit" doesn't work for Listener-Widget
                        child: MouseRegion(
                          onExit: (event) {
                            debugPrint("PointerExitEvent");
                            cameraPerspective.position = cameraPositionOld!;
                            cameraPerspective.updateMatrix();
                            cameraPositionOld = null;
                          },
                          onHover: (event) {
                            if (cameraPositionOld == null) {
                              cameraPositionOld = THREE.Vector3();
                              cameraPositionOld = cameraPerspective.position;
                            }
                            double x = (event.position.dx / width - 0.5) * 2;
                            double y = (event.position.dy / height - 0.5) * 2;

                            mousePos.x = x;
                            mousePos.y = y;

                            debugPrint(mousePos.x.toString());
                          },
                          child: ListView(shrinkWrap: true, children: [
                            ...randomTextList
                                .map((e) => Padding(
                                      padding: EdgeInsets.only(
                                          bottom: Random(50).nextDouble() * 600,
                                          top: Random(50).nextDouble() * 600),
                                      child: Text(
                                        e,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w300,
                                            color:
                                                Colors.white.withOpacity(0.8),
                                            fontSize:
                                                Random().nextDouble() * 70),
                                      ),
                                    ))
                                .toList()
                          ]),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ],
          ));
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Text("render"),
        onPressed: () {
          render();
        },
      ),
    );
    ;
  }
}

var ray = THREE.Ray();
var size = THREE.Vector3();

var dir = THREE.Vector3(1, 1, 1).normalize();
var dummyTarget =
    THREE.Vector3(); // to prevent logging of warnings from ray.at() method

THREE.BufferGeometry fillWithPoints(THREE.BufferGeometry geometry, int count) {
  geometry.computeBoundingBox();
  THREE.Box3 bbox = geometry.boundingBox!;

  var points = [];

  /*for (let i = 0; i < count; i++) {
      let p = setRandomVector(bbox.min, bbox.max);
      points.push(p);
    }*/
  var counter = 0;
  while (counter < count) {
    var v = THREE.Vector3(
        THREE.Math.randFloat(bbox.min.x, bbox.max.x),
        THREE.Math.randFloat(bbox.min.y, bbox.max.y),
        THREE.Math.randFloat(bbox.min.z, bbox.max.z));
    if (isInside(v, geometry)) {
      points.add(v);
      counter++;
    }
  }

  /*function setRandomVector(min, max){
      let v =  THREE.Vector3(
        THREE.Math.randFloat(min.x, max.x),
        THREE.Math.randFloat(min.y, max.y),
        THREE.Math.randFloat(min.z, max.z)
      );
      if (!isInside(v)){return setRandomVector(min, max);}
      return v;
    }*/
  return THREE.BufferGeometry().setFromPoints(points);
}

bool isInside(THREE.Vector3 v, THREE.BufferGeometry geometry) {
  ray.set(v, dir);
  var counter = 0;

  var pos = geometry.attributes["position"];
  var faces = pos.count / 3;
  //console.log(faces);
  var vA = THREE.Vector3(), vB = THREE.Vector3(), vC = THREE.Vector3();
  for (var i = 0; i < faces; i++) {
    vA.fromBufferAttribute(pos, i * 3 + 0);
    vB.fromBufferAttribute(pos, i * 3 + 1);
    vC.fromBufferAttribute(pos, i * 3 + 2);
    if (ray.intersectTriangle(vA, vB, vC, false, dummyTarget) != null)
      counter++;
  }

  return counter % 2 == 1;
}

//Shader Examples
// https://github.com/mrdoob/three.js/blob/master/examples/webgl_buffergeometry_custom_attributes_particles.html
// https://github.com/mrdoob/three.js/blob/master/examples/webgl_interactive_points.html

String vertexShader = """
    uniform float pointSize;

   void main(){

    //calculate position in world space
    vec4 wPosition =   modelMatrix * vec4(position, 1.);
    
    gl_PointSize = pointSize -(distance(cameraPosition.xyz, wPosition.xyz)/pointSize)*0.2;
    gl_Position = projectionMatrix* modelViewMatrix * vec4(position,1.);
}
    """;

String fragmentShader = """ 

      uniform sampler2D pointsTexture;

			void main() {

				gl_FragColor = vec4(1.0 ) ;
			}
    """;
