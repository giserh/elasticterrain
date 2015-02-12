goog.provide('ol.interaction.DragShearIntegrated');

goog.require('goog.asserts');
goog.require('goog.async.AnimationDelay');
goog.require('ol.Pixel');
goog.require('ol.coordinate');
goog.require('ol.events.condition');
goog.require('ol.interaction.Pointer');
goog.require('ol.ViewHint');

/**
 * @classdesc
 * Terrain Interaction DragShearIntegrated
 *
 * @constructor
 * @extends {ol.interaction.Pointer}
 * @param {Object.<string, number|ol.Map>} options 
 * @api stable
 */
ol.interaction.DragShearIntegrated = function(options) {
  goog.base(this, {
    handleDownEvent: ol.interaction.DragShearIntegrated.handleDownEvent_,
    handleDragEvent: ol.interaction.DragShearIntegrated.handleDragEvent_,
    handleUpEvent: ol.interaction.DragShearIntegrated.handleUpEvent_
  });

  goog.asserts.assertInstanceof(options.map, ol.Map, 'dragShearIntegrated expects map object');
  goog.asserts.assert(goog.isDef(options.threshold));
  goog.asserts.assert(goog.isDef(options.springCoefficient));
  goog.asserts.assert(goog.isDef(options.frictionForce));
  goog.asserts.assert(goog.isDef(options.minZoom));

  goog.asserts.assert(goog.isDef(options.springLength));
  goog.asserts.assert(goog.isDef(options.hybridShearingRadiusPx)); 

  /** @type {Object.<string, number|ol.Map>} */  
  this.options = options;

  /** @type {ol.Map} */
  this.map = this.options.map;

  /** @type {ol.View} */
  this.view = this.map.getView();

  /** @type {ol.layer.TileDem} */
  this.demLayer =  /** @type {ol.layer.TileDem} */(this.map.getLayers().getArray()[this.map.getLayers().getArray().length-1]);

  /** @type {ol.events.ConditionType} */
  this.condition = goog.isDef(this.options.keypress) ? this.options.keypress : ol.events.condition.noModifierKeys;

  /** @type {number} */
  this.minZoom = this.options.minZoom;

  /** @type {ol.Pixel} */
  this.startDragPositionPx = [0,0];

  /** @type {number|null} */
  this.startDragElevation = 0;

  /** @type {number} */
  this.maxElevation = 3000;

  /** @type {number} */
  this.minElevation = 0;

  /** @type {number} */
  this.criticalElevation = (this.maxElevation-this.minElevation)/2;

   /** @type {ol.Pixel} */
  this.startCenter = [0,0];

   /** @type {ol.Pixel} */
  this.currentCenter = [0,0];  

  /** @type {ol.Pixel} */
  this.currentChange = [0,0];

  /** @type {ol.Pixel} */
  this.currentDragPositionPx = [0,0];

  /**
   * Animates shearing & panning according to current currentDragPosition
   * @notypecheck   
   */
  ol.interaction.DragShearIntegrated.prototype.animation = function(){
    var o = this.options;
    
    var currentDragPosition = this.map.getCoordinateFromPixel(this.currentDragPositionPx);
    var startDragPosition = this.map.getCoordinateFromPixel(this.startDragPositionPx);
    var currentCenter = this.currentCenter;
    var startCenter = this.startCenter;

    var getAnimatingPosition = function() {
         return [startDragPosition[0] - (currentCenter[0] - startCenter[0]),
                 startDragPosition[1] - (currentCenter[1] - startCenter[1])];
    };

    var getDistance = function(){
        return [currentDragPosition[0] - getAnimatingPosition()[0],
                currentDragPosition[1] - getAnimatingPosition()[1]];
    };

    var distanceXY = getDistance();
    var distance = Math.sqrt(distanceXY[0] * distanceXY[0] + distanceXY[1] * distanceXY[1]);

    var springLengthXY = [distanceXY[0] * o.springLength/distance,
                          distanceXY[1] * o.springLength/distance];

    if(isNaN(springLengthXY[0])) springLengthXY[0] = 0;
    if(isNaN(springLengthXY[1])) springLengthXY[1] = 0;
    
    var accelerationXY = [(distanceXY[0] - springLengthXY[0]) * o.springCoefficient,
                          (distanceXY[1] - springLengthXY[1]) * o.springCoefficient];

    var friction = (1-o.frictionForce);
    this.currentChange = [this.currentChange[0]*friction+accelerationXY[0],
                          this.currentChange[1]*friction+accelerationXY[1]];

    // set change value to zero when not changing anymore significantly
    if(Math.abs(this.currentChange[0]) < o.threshold) this.currentChange[0] = 0;
    if(Math.abs(this.currentChange[1]) < o.threshold) this.currentChange[1] = 0;


    var animationActive = (Math.abs(this.currentChange[0]) > o.threshold && Math.abs(this.currentChange[1]) > o.threshold);
    var hybridShearingActive = (Math.abs(springLengthXY[0]) > 0 && Math.abs(springLengthXY[1]) > 0); 
    var otherInteractionActive = (this.view.getHints()[ol.ViewHint.INTERACTING]); // other active interaction like zooming or rotation


    if((animationActive || (hybridShearingActive)) && !otherInteractionActive) {                

        currentCenter[0] -= this.currentChange[0];
        currentCenter[1] -= this.currentChange[1];

        distanceXY = getDistance(); 

        var newShearing = {x:(distanceXY[0]/this.startDragElevation), 
                           y:(distanceXY[1]/this.startDragElevation)};

        var newCenter = [currentCenter[0],
                         currentCenter[1]];

        if(this.startDragElevation < this.criticalElevation){     
               
            newShearing = {x:(-distanceXY[0]/(this.maxElevation-this.startDragElevation)), 
                           y:(-distanceXY[1]/(this.maxElevation-this.startDragElevation))};   
            
            newCenter = [newCenter[0] - distanceXY[0],
                         newCenter[1] - distanceXY[1]];
        }

        this.view.setCenter(newCenter);   

        this.demLayer.setTerrainShearing(newShearing);
        this.demLayer.redraw();

        this.animationDelay.start();

    } else {

      // restore shearing to 0 if other interaction like zooming or rotation is active
      if(this.view.getHints()[ol.ViewHint.INTERACTING]){
        this.demLayer.setTerrainShearing({x:0,y:0});
        this.demLayer.redraw();
      }

      this.animationDelay.stop(); 
    }
  };


  /**
   * @private
   * @type {goog.async.AnimationDelay}
   */
  this.animationDelay = new goog.async.AnimationDelay(this.animation,undefined,this);
  this.registerDisposable(this.animationDelay);
};

goog.inherits(ol.interaction.DragShearIntegrated, ol.interaction.Pointer);


/**
 * @param {ol.MapBrowserPointerEvent} mapBrowserEvent Event.
 * @this {ol.interaction.DragShearIntegrated}
 * @notypecheck   
 */
ol.interaction.DragShearIntegrated.handleDragEvent_ = function(mapBrowserEvent) {
  if (this.targetPointers.length > 0 && this.condition(mapBrowserEvent) && this.minZoom <= this.view.getZoom()) {
    goog.asserts.assert(this.targetPointers.length >= 1);
    this.currentDragPositionPx = ol.interaction.Pointer.centroid(this.targetPointers);   
    this.animationDelay.start(); 

    if(this.options.hybridShearingRadiusPx > 0.0){
      var currentDragPosition = this.map.getCoordinateFromPixel(this.currentDragPositionPx);
      var startDragPosition = this.map.getCoordinateFromPixel(this.startDragPositionPx);
      var animatingPosition = [startDragPosition[0] - (this.currentCenter[0] - this.startCenter[0]),
                               startDragPosition[1] - (this.currentCenter[1] - this.startCenter[1])];
      var distanceX = currentDragPosition[0] - animatingPosition[0];
      var distanceY = currentDragPosition[1] - animatingPosition[1];
      var distance = Math.sqrt(distanceX * distanceX + distanceY * distanceY);
      this.options.springLength = Math.min(this.options.hybridShearingRadiusPx*this.view.getResolution(), distance);
    }
}
};


/**
 * @param {ol.MapBrowserPointerEvent} mapBrowserEvent Event.
 * @return {boolean} Stop drag sequence?
 * @this {ol.interaction.DragShearIntegrated}
 * @private
 */
ol.interaction.DragShearIntegrated.handleUpEvent_ = function(mapBrowserEvent) { 
  if (this.targetPointers.length === 0) {  
    this.options.springLength = 0; 
    return true;
  } else{
    return false;
  }
};


/**
 * @param {ol.MapBrowserPointerEvent} mapBrowserEvent Event.
 * @return {boolean} Start drag sequence?
 * @this {ol.interaction.DragShearIntegrated}
 * @private
 */
ol.interaction.DragShearIntegrated.handleDownEvent_ = function(mapBrowserEvent) {
  if (this.targetPointers.length > 0 && this.condition(mapBrowserEvent) && this.minZoom <= this.view.getZoom()) {
      this.startDragPositionPx = ol.interaction.Pointer.centroid(this.targetPointers);
      this.startDragElevation = /** @type {ol.renderer.webgl.TileDemLayer} */(this.map.getRenderer().getLayerRenderer(this.demLayer)).getElevation(mapBrowserEvent.coordinate,this.view.getZoom());
      this.startCenter = [this.view.getCenter()[0],this.view.getCenter()[1]];
      this.currentCenter =[this.view.getCenter()[0],this.view.getCenter()[1]];
      this.currentDragPositionPx = ol.interaction.Pointer.centroid(this.targetPointers);
      return true;
  } else {     
      return false;
  }
};


