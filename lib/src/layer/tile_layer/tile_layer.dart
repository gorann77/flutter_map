import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart' show MapEquality;
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map/src/layer/tile_layer/tile.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_bounds/tile_bounds.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_bounds/tile_bounds_at_zoom.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_image_manager.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_range.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_range_calculator.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_scale_calculator.dart';
import 'package:http/retry.dart';

part 'tile_error_evict_callback.dart';
part 'wms_tile_layer_options.dart';

/// Describes the needed properties to create a tile-based layer. A tile is an
/// image bound to a specific geographical position.
///
/// You should read up about the options by exploring each one, or visiting
/// https://docs.fleaflet.dev/usage/layers/tile-layer. Some are important to
/// avoid issues.
@immutable
class TileLayer extends StatefulWidget {
  /// The URL template is a string that contains placeholders, which, when filled
  /// in, create a URL/URI to a specific tile.
  ///
  /// For more information, see <https://docs.fleaflet.dev/layers/tile-layer>.
  final String? urlTemplate;

  /// Fallback URL template, used if an error occurs when fetching tiles from
  /// the [urlTemplate].
  ///
  /// Note that specifying this (non-null) will result in tiles not being cached
  /// in memory. This is to avoid issues where the [urlTemplate] is flaky, to
  /// prevent different tilesets being displayed at the same time.
  ///
  /// Avoid specifying this when using [AssetTileProvider] or [FileTileProvider],
  /// as these providers are less performant and efficient when this is
  /// specified. See their documentation for more information.
  final String? fallbackUrl;

  /// If `true`, inverses Y axis numbering for tiles (turn this on for
  /// [TMS](https://en.wikipedia.org/wiki/Tile_Map_Service) services).
  final bool tms;

  /// If not `null`, then tiles will pull's WMS protocol requests
  final WMSTileLayerOptions? wmsOptions;

  /// Size for the tile.
  /// Default is 256
  final double tileSize;

  /// The minimum zoom level down to which this layer will be displayed
  /// (inclusive)
  ///
  /// This should usually be 0 (as default).
  final double minZoom;

  /// The maximum zoom level up to which this layer will be displayed
  /// (inclusive).
  ///
  /// Prefer [maxNativeZoom] for setting the maximum zoom level supported by the
  /// tile source. The main usage for this is to display a different [TileLayer]
  /// when zoomed far in.
  ///
  /// Otherwise, this should usually be infinite (as default), so that there are
  /// tiles always displayed.
  final double maxZoom;

  /// Minimum zoom level supported by the tile source
  ///
  /// Tiles from below this zoom level will not be displayed, instead tiles at
  /// this zoom level will be displayed and scaled.
  ///
  /// This should usually be 0 (as default), as most tile sources will support
  /// zoom levels onwards from this.
  final int minNativeZoom;

  /// Maximum zoom number supported by the tile source has available.
  ///
  /// Tiles from above this zoom level will not be displayed, instead tiles at
  /// this zoom level will be displayed and scaled.
  ///
  /// Most tile servers support up to zoom level 19, which is the default.
  /// Otherwise, this should be specified.
  final int maxNativeZoom;

  /// If set to true, the zoom number used in tile URLs will be reversed
  /// (`maxZoom - zoom` instead of `zoom`)
  final bool zoomReverse;

  /// The zoom number used in tile URLs will be offset with this value.
  final double zoomOffset;

  /// List of subdomains for the URL.
  ///
  /// Example:
  ///
  /// Subdomains = {a,b,c}
  ///
  /// and the URL is as follows:
  ///
  /// https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png
  ///
  /// then:
  ///
  /// https://a.tile.openstreetmap.org/{z}/{x}/{y}.png
  /// https://b.tile.openstreetmap.org/{z}/{x}/{y}.png
  /// https://c.tile.openstreetmap.org/{z}/{x}/{y}.png
  final List<String> subdomains;

  // Control how tiles are displayed and whether they are faded in when loaded.
  // Defaults to TileDisplay.fadeIn().
  final TileDisplay tileDisplay;

  /// Color shown behind the tiles
  @Deprecated(
    'Prefer `MapOptions.backgroundColor`. '
    'This property has been removed simplify interaction when using multiple `TileLayer`s. '
    'This property is deprecated since v6.',
  )
  final Color? backgroundColor;

  /// Provider with which to load map tiles
  ///
  /// The default is [NetworkTileProvider] which supports both IO and web
  /// platforms. It uses a [RetryClient] to retry failed requests, but that can
  /// be overriden by specifying [NetworkTileProvider.httpClient].
  ///
  /// Does not automatically cache (past Flutter's [ImageCache]). For options to
  /// add offline mapping, see
  /// https://docs.fleaflet.dev/tile-servers/offline-mapping.
  ///
  /// `userAgentPackageName` is a [TileLayer] parameter, which should be passed
  /// the application's correct package name, such as 'com.example.app'. This is
  /// important to avoid blocking by tile servers due to high-levels of
  /// unidentified traffic. This is passed through to the [NetworkTileProvider]
  /// in a suitably formatted string, where it forms the 'User-Agent' header,
  /// overriding any custom user agent specified in the HTTP client. To override
  /// this behaviour, specify a 'User-Agent' key in the
  /// [NetworkTileProvider.headers] property. If no value is passed, it defaults
  /// to 'unknown'. This is all ignored on the web, where the 'User-Agent' header
  /// cannot be changed due to a limitation of Dart/browsers.
  ///
  /// [AssetTileProvider] and [FileTileProvider] are alternatives to network
  /// providers, which use the [urlTemplate] as a path instead.
  /// For example, 'assets/map/{z}/{x}/{y}.png' or
  /// '/storage/emulated/0/map_app/tiles/{z}/{x}/{y}.png'.
  ///
  /// Custom [TileProvider]s can also be used, but these will not necessarily
  /// follow the header rules above.
  final TileProvider tileProvider;

  /// When panning the map, keep this many rows and columns of tiles before
  /// unloading them.
  final int keepBuffer;

  /// When loading tiles only visible tiles are loaded by default. This option
  /// increases the loaded tiles by the given number on both axis which can help
  /// prevent the user from seeing loading tiles whilst panning. Setting the
  /// pan buffer too high can impact performance, typically this is set to zero
  /// or one.
  final int panBuffer;

  /// Tile image to show in place of the tile that failed to load.
  final ImageProvider? errorImage;

  /// Static information that should replace placeholders in the [urlTemplate].
  /// Applying API keys is a good example on how to use this parameter.
  ///
  /// Example:
  ///
  /// ```dart
  ///
  /// TileLayerOptions(
  ///     urlTemplate: "https://api.tiles.mapbox.com/v4/"
  ///                  "{id}/{z}/{x}/{y}{r}.png?access_token={accessToken}",
  ///     additionalOptions: {
  ///         'accessToken': '<PUT_ACCESS_TOKEN_HERE>',
  ///          'id': 'mapbox.streets',
  ///     },
  /// ),
  /// ```
  final Map<String, String> additionalOptions;

  /// If `true`, it will request four tiles of half the specified size and a
  /// bigger zoom level in place of one to utilize the high resolution.
  ///
  /// If `true` then MapOptions's `maxZoom` should be `maxZoom - 1` since
  /// retinaMode just simulates retina display by playing with `zoomOffset`. If
  /// geoserver supports retina `@2` tiles then it it advised to use them
  /// instead of simulating it (use {r} in the [urlTemplate])
  ///
  /// It is advised to use retinaMode if display supports it, write code like
  /// this:
  ///
  /// ```dart
  /// TileLayerOptions(
  ///     retinaMode: true && MediaQuery.of(context).devicePixelRatio > 1.0,
  /// ),
  /// ```
  final bool retinaMode;

  /// This callback will be executed if an error occurs when fetching tiles.
  final ErrorTileCallBack? errorTileCallback;

  @Deprecated(
    'Prefer creating a custom `TileProvider` instead. '
    'This option has been deprecated as it is out of scope for the `TileLayer`. '
    'This option is deprecated since v6.',
  )
  final TemplateFunction? templateFunction;

  /// Function which may Wrap Tile with custom Widget
  /// There are predefined examples in 'tile_builder.dart'
  final TileBuilder? tileBuilder;

  // If a Tile was loaded with error and if strategy isn't `none` then TileProvider
  // will be asked to evict Image based on current strategy
  // (see #576 - even Error Images are cached in flutter)
  final EvictErrorTileStrategy evictErrorTileStrategy;

  /// Stream to notify the [TileLayer] that it needs resetting
  final Stream<void>? reset;

  /// Only load tiles that are within these bounds
  final LatLngBounds? tileBounds;

  /// This transformer modifies how/when tile updates and pruning are triggered
  /// based on [MapEvent]s. It is a StreamTransformer and therefore it is
  /// possible to filter/modify/throttle the [TileUpdateEvent]s. Defaults to
  /// [TileUpdateTransformers.ignoreTapEvents] which disables loading/pruning
  /// for map taps, secondary taps and long presses. See TileUpdateTransformers
  /// for more transformer presets or implement your own.
  ///
  /// Note: Changing the [tileUpdateTransformer] after TileLayer is created has
  /// no affect.
  final TileUpdateTransformer tileUpdateTransformer;

  TileLayer({
    super.key,
    this.urlTemplate,
    this.fallbackUrl,
    double tileSize = 256,
    double minZoom = 0,
    double maxZoom = double.infinity,
    this.minNativeZoom = 0,
    this.maxNativeZoom = 19,
    this.zoomReverse = false,
    double zoomOffset = 0.0,
    this.additionalOptions = const {},
    this.subdomains = const <String>[],
    this.keepBuffer = 2,
    this.panBuffer = 0,
    this.backgroundColor,
    this.errorImage,
    final TileProvider? tileProvider,
    this.tms = false,
    this.wmsOptions,
    this.tileDisplay = const TileDisplay.fadeIn(),
    this.retinaMode = false,
    this.errorTileCallback,
    @Deprecated(
      'Prefer creating a custom `TileProvider` instead. '
      'This option has been deprecated as it is out of scope for the `TileLayer`. '
      'This option is deprecated since v6.',
    )
    this.templateFunction,
    this.tileBuilder,
    this.evictErrorTileStrategy = EvictErrorTileStrategy.none,
    this.reset,
    this.tileBounds,
    TileUpdateTransformer? tileUpdateTransformer,
    String userAgentPackageName = 'unknown',
  })  : assert(
          tileDisplay.when(
            instantaneous: (_) => true,
            fadeIn: (fadeIn) => fadeIn.duration > Duration.zero,
          )!,
          'The tile fade in duration needs to be bigger than zero',
        ),
        maxZoom =
            wmsOptions == null && retinaMode && maxZoom > 0.0 && !zoomReverse
                ? maxZoom - 1.0
                : maxZoom,
        minZoom =
            wmsOptions == null && retinaMode && maxZoom > 0.0 && zoomReverse
                ? max(minZoom + 1.0, 0)
                : minZoom,
        zoomOffset = wmsOptions == null && retinaMode && maxZoom > 0.0
            ? (zoomReverse ? zoomOffset - 1.0 : zoomOffset + 1.0)
            : zoomOffset,
        tileSize = wmsOptions == null && retinaMode && maxZoom > 0.0
            ? (tileSize / 2.0).floorToDouble()
            : tileSize,
        tileProvider = (tileProvider ?? NetworkTileProvider())
          ..headers.putIfAbsent(
              'User-Agent', () => 'flutter_map ($userAgentPackageName)'),
        tileUpdateTransformer =
            tileUpdateTransformer ?? TileUpdateTransformers.ignoreTapEvents;

  @override
  State<StatefulWidget> createState() => _TileLayerState();
}

class _TileLayerState extends State<TileLayer> with TickerProviderStateMixin {
  bool _initializedFromMapCamera = false;

  final TileImageManager _tileImageManager = TileImageManager();
  late TileBounds _tileBounds;
  late TileRangeCalculator _tileRangeCalculator;
  late TileScaleCalculator _tileScaleCalculator;

  // We have to hold on to the mapController hashCode to determine whether we
  // need to reinitialize the listeners. didChangeDependencies is called on
  // every map movement and if we unsubscribe and resubscribe every time we
  // miss events.
  int? _mapControllerHashCode;

  // Only one of these two subscriptions will be initialized. If
  // TileLayer.tileUpdateTransformer is null then we subscribe to map movement
  // otherwise we subscribe to tile update events which are transformed from
  // map movements.
  StreamSubscription<TileUpdateEvent>? _tileUpdateSubscription;

  StreamSubscription<void>? _resetSub;
  Timer? _pruneLater;

  @override
  void initState() {
    super.initState();

    if (widget.reset != null) {
      _resetSub = widget.reset?.listen((_) {
        _tileImageManager.removeAll(widget.evictErrorTileStrategy);
        _loadAndPruneInVisibleBounds(MapCamera.of(context));
      });
    }

    _tileRangeCalculator = TileRangeCalculator(tileSize: widget.tileSize);
  }

  // This is called on every map movement so we should avoid expensive logic
  // where possible.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final camera = MapCamera.of(context);

    final mapController = MapController.of(context);
    if (_mapControllerHashCode != mapController.hashCode) {
      _tileUpdateSubscription?.cancel();

      _mapControllerHashCode = mapController.hashCode;
      _tileUpdateSubscription = mapController.mapEventStream
          .map((mapEvent) => TileUpdateEvent(mapEvent: mapEvent))
          .transform(widget.tileUpdateTransformer)
          .listen((event) => _onTileUpdateEvent(event));
    }

    var reloadTiles = false;
    if (!_initializedFromMapCamera ||
        _tileBounds.shouldReplace(
            camera.crs, widget.tileSize, widget.tileBounds)) {
      reloadTiles = true;
      _tileBounds = TileBounds(
        crs: camera.crs,
        tileSize: widget.tileSize,
        latLngBounds: widget.tileBounds,
      );
    }

    if (!_initializedFromMapCamera ||
        _tileScaleCalculator.shouldReplace(camera.crs, widget.tileSize)) {
      reloadTiles = true;
      _tileScaleCalculator = TileScaleCalculator(
        crs: camera.crs,
        tileSize: widget.tileSize,
      );
    }

    if (reloadTiles) _loadAndPruneInVisibleBounds(camera);

    _initializedFromMapCamera = true;
  }

  @override
  void didUpdateWidget(TileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    var reloadTiles = false;

    // There is no caching in TileRangeCalculator so we can just replace it.
    _tileRangeCalculator = TileRangeCalculator(tileSize: widget.tileSize);

    if (_tileBounds.shouldReplace(
        _tileBounds.crs, widget.tileSize, widget.tileBounds)) {
      _tileBounds = TileBounds(
        crs: _tileBounds.crs,
        tileSize: widget.tileSize,
        latLngBounds: widget.tileBounds,
      );
      reloadTiles = true;
    }

    if (_tileScaleCalculator.shouldReplace(
        _tileScaleCalculator.crs, widget.tileSize)) {
      _tileScaleCalculator = TileScaleCalculator(
        crs: _tileScaleCalculator.crs,
        tileSize: widget.tileSize,
      );
    }

    if (oldWidget.retinaMode != widget.retinaMode) {
      reloadTiles = true;
    }

    if (oldWidget.minZoom != widget.minZoom ||
        oldWidget.maxZoom != widget.maxZoom) {
      reloadTiles |=
          !_tileImageManager.allWithinZoom(widget.minZoom, widget.maxZoom);
    }

    if (!reloadTiles) {
      final oldUrl =
          oldWidget.wmsOptions?._encodedBaseUrl ?? oldWidget.urlTemplate;
      final newUrl = widget.wmsOptions?._encodedBaseUrl ?? widget.urlTemplate;

      final oldOptions = oldWidget.additionalOptions;
      final newOptions = widget.additionalOptions;

      if (oldUrl != newUrl ||
          !(const MapEquality<String, String>())
              .equals(oldOptions, newOptions)) {
        _tileImageManager.reloadImages(widget, _tileBounds);
      }
    }

    if (reloadTiles) {
      _tileImageManager.removeAll(widget.evictErrorTileStrategy);
      _loadAndPruneInVisibleBounds(MapCamera.maybeOf(context)!);
    } else if (oldWidget.tileDisplay != widget.tileDisplay) {
      _tileImageManager.updateTileDisplay(widget.tileDisplay);
    }
  }

  @override
  void dispose() {
    _tileUpdateSubscription?.cancel();
    _tileImageManager.removeAll(widget.evictErrorTileStrategy);
    _resetSub?.cancel();
    _pruneLater?.cancel();
    widget.tileProvider.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = MapCamera.of(context);

    if (_outsideZoomLimits(map.zoom.round())) return const SizedBox.shrink();

    final tileZoom = _clampToNativeZoom(map.zoom);
    final tileBoundsAtZoom = _tileBounds.atZoom(tileZoom);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: map,
      tileZoom: tileZoom,
    );

    // For a given map event both this rebuild method and the tile
    // loading/pruning logic will be fired. Any TileImages which are not
    // rendered in a corresponding Tile after this build will not become
    // visible until the next build. Therefore, in case this build is executed
    // before the loading/updating, we must pre-create the missing TileImages
    // and add them to the widget tree so that when they are loaded they notify
    // the Tile and become visible. We don't need to prune here as any new tiles
    // will be pruned when the map event triggers tile loading.
    _tileImageManager.createMissingTiles(
      visibleTileRange,
      tileBoundsAtZoom,
      createTileImage: (coordinates) => _createTileImage(
        coordinates: coordinates,
        tileBoundsAtZoom: tileBoundsAtZoom,
        pruneAfterLoad: false,
      ),
    );

    final currentPixelOrigin = Point<double>(
      map.pixelOrigin.x.toDouble(),
      map.pixelOrigin.y.toDouble(),
    );

    _tileScaleCalculator.clearCacheUnlessZoomMatches(map.zoom);

    return _addBackgroundColor(
      Stack(
        children: [
          ..._tileImageManager
              .inRenderOrder(widget.maxZoom, tileZoom)
              .map((tileImage) {
            return Tile(
              // Must be an ObjectKey, not a ValueKey using the coordinates, in
              // case we remove and replace the TileImage with a different one.
              key: ObjectKey(tileImage),
              scaledTileSize: _tileScaleCalculator.scaledTileSize(
                map.zoom,
                tileImage.coordinates.z,
              ),
              currentPixelOrigin: currentPixelOrigin,
              tileImage: tileImage,
              tileBuilder: widget.tileBuilder,
            );
          }),
        ],
      ),
    );
  }

  /// This can be removed once the deprecated backgroundColor option is removed.
  Widget _addBackgroundColor(Widget child) {
    // ignore: deprecated_member_use_from_same_package
    final color = widget.backgroundColor;

    return color == null ? child : ColoredBox(color: color, child: child);
  }

  TileImage _createTileImage({
    required TileCoordinates coordinates,
    required TileBoundsAtZoom tileBoundsAtZoom,
    required bool pruneAfterLoad,
  }) {
    final cancelLoading = Completer<void>();

    final imageProvider = widget.tileProvider.supportsCancelLoading
        ? widget.tileProvider.getImageWithCancelLoadingSupport(
            tileBoundsAtZoom.wrap(coordinates),
            widget,
            cancelLoading.future,
          )
        : widget.tileProvider.getImage(
            tileBoundsAtZoom.wrap(coordinates),
            widget,
          );

    return TileImage(
      vsync: this,
      coordinates: coordinates,
      imageProvider: imageProvider,
      onLoadError: _onTileLoadError,
      onLoadComplete: (coordinates) {
        if (pruneAfterLoad) _pruneIfAllTilesLoaded(coordinates);
      },
      tileDisplay: widget.tileDisplay,
      errorImage: widget.errorImage,
      cancelLoading: cancelLoading,
    );
  }

  /// Load and/or prune tiles according to the visible bounds of the [event]
  /// center/zoom, or the current center/zoom if not specified.
  void _onTileUpdateEvent(TileUpdateEvent event) {
    final tileZoom = _clampToNativeZoom(event.zoom);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: event.camera,
      tileZoom: tileZoom,
      center: event.center,
      viewingZoom: event.zoom,
    );

    if (event.load && !_outsideZoomLimits(tileZoom)) {
      _loadTiles(visibleTileRange, pruneAfterLoad: event.prune);
    }

    if (event.prune) {
      _tileImageManager.evictAndPrune(
        visibleRange: visibleTileRange,
        pruneBuffer: widget.panBuffer + widget.keepBuffer,
        evictStrategy: widget.evictErrorTileStrategy,
      );
    }
  }

  /// Load new tiles in the visible bounds and prune those outside.
  void _loadAndPruneInVisibleBounds(MapCamera camera) {
    final tileZoom = _clampToNativeZoom(camera.zoom);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: camera,
      tileZoom: tileZoom,
    );

    if (!_outsideZoomLimits(tileZoom)) {
      _loadTiles(
        visibleTileRange,
        pruneAfterLoad: true,
      );
    }

    _tileImageManager.evictAndPrune(
      visibleRange: visibleTileRange,
      pruneBuffer: max(widget.panBuffer, widget.keepBuffer),
      evictStrategy: widget.evictErrorTileStrategy,
    );
  }

  // For all valid TileCoordinates in the [tileLoadRange], expanded by the
  // [TileLayer.panBuffer], this method will do the following depending on
  // whether a matching TileImage already exists or not:
  //   * Exists: Mark it as current and initiate image loading if it has not
  //     already been initiated.
  //   * Does not exist: Creates the TileImage (they are current when created)
  //     and initiates loading.
  //
  // Additionally, any current TileImages outside of the [tileLoadRange],
  // expanded by the [TileLayer.panBuffer] + [TileLayer.keepBuffer], are marked
  // as not current.
  void _loadTiles(
    DiscreteTileRange tileLoadRange, {
    required bool pruneAfterLoad,
  }) {
    final tileZoom = tileLoadRange.zoom;
    tileLoadRange = tileLoadRange.expand(widget.panBuffer);

    // Build the queue of tiles to load. Marks all tiles with valid coordinates
    // in the tileLoadRange as current.
    final tileBoundsAtZoom = _tileBounds.atZoom(tileZoom);
    final tilesToLoad = _tileImageManager.createMissingTilesIn(
      tileBoundsAtZoom.validCoordinatesIn(tileLoadRange),
      createTile: (coordinates) => _createTileImage(
        coordinates: coordinates,
        tileBoundsAtZoom: tileBoundsAtZoom,
        pruneAfterLoad: pruneAfterLoad,
      ),
    );

    // Re-order the tiles by their distance to the center of the range.
    final tileCenter = tileLoadRange.center;
    tilesToLoad.sort(
      (a, b) => a.coordinates
          .distanceTo(tileCenter)
          .compareTo(b.coordinates.distanceTo(tileCenter)),
    );

    // Create the new Tiles.
    for (final tile in tilesToLoad) {
      tile.load();
    }
  }

  // Rounds the zoom to the nearest int and clamps it to the native zoom limits
  // if there are any.
  int _clampToNativeZoom(double zoom) {
    zoom += 0.5;

    int result = zoom.round();

    if (widget.minNativeZoom != null) {
      result = math.max(result, widget.minNativeZoom!);
    }
    if (widget.maxNativeZoom != null) {
      result = math.min(result, widget.maxNativeZoom!);
    }

    if (result > 16) result = 16;

    return result;
  }

  void _onTileLoadError(TileImage tile, Object error, StackTrace? stackTrace) {
    debugPrint(error.toString());
    widget.errorTileCallback?.call(tile, error, stackTrace);
  }

  void _pruneIfAllTilesLoaded(TileCoordinates coordinates) {
    if (!_tileImageManager.containsTileAt(coordinates) ||
        !_tileImageManager.allLoaded) {
      return;
    }

    widget.tileDisplay.when(instantaneous: (_) {
      _pruneWithCurrentCamera();
    }, fadeIn: (fadeIn) {
      // Wait a bit more than tileFadeInDuration to trigger a pruning so that
      // we don't see tile removal under a fading tile.
      _pruneLater?.cancel();
      _pruneLater = Timer(
        fadeIn.duration + const Duration(milliseconds: 50),
        () => _pruneWithCurrentCamera(),
      );
    });
  }

  void _pruneWithCurrentCamera() {
    final camera = MapCamera.of(context);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: camera,
      tileZoom: _clampToNativeZoom(camera.zoom),
      center: camera.center,
      viewingZoom: camera.zoom,
    );
    _tileImageManager.prune(
      visibleRange: visibleTileRange,
      pruneBuffer: max(widget.panBuffer, widget.keepBuffer),
      evictStrategy: widget.evictErrorTileStrategy,
    );
  }

  bool _outsideZoomLimits(num zoom) =>
      zoom < widget.minZoom || zoom > widget.maxZoom;
}
