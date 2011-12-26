clone = (obj) ->
  if not obj? or typeof obj isnt 'object'
    return obj

  newInstance = new obj.constructor()

  for key of obj
    newInstance[key] = clone obj[key]

  return newInstance

class Annotator.Plugin.MarginViewerObjectStore
  constructor: (data=[] , paramFuncObject , @idfield="id" , @marginobjfield="_marginObject" , @indexfield="_marginindex") ->
    @funcObject = clone(paramFuncObject)
    @funcObject.sortDataComparison = (x,y) => paramFuncObject.sortComparison(x[0],y[0])
    @funcObject.mapFunc = (x) => [paramFuncObject.sortDataMap(x),x]
    @data=data.map(@funcObject.mapFunc)
    @data.sort(@funcObject.sortDataComparison)
    @deletions=0
    @insertions=0
    if(@data.length>0)
      for index in [0..@data.length-1]
        obj=@data[index][1]
        obj[@indexfield]=index
  
  getMarginObjects: -> @data.map((x) -> x[1])

  updateObjectLocation: (obj) ->
    objIndex = @getObjectLocation(obj)
    @data[objIndex]=[@funcObject.sortDataMap(obj),obj]
    obj[@indexfield]=objIndex

  objectEquals: (obj1,obj2) ->
    if ("id" of obj1) and ("id" of obj2)
      return obj1.id is obj2.id
    if ("id" of obj1) or ("id" of obj2)
      return false
    if (@indexfield of obj1) and (@indexfield of obj2)
      return obj1[@indexfield] is obj2[@indexfield]
    return false
    
  getObjectLocation: (obj) -> 
    supposedLocation = obj[@indexfield]
    # object is at its internally stored location
    if @objectEquals(@data[supposedLocation][1],obj)
      return supposedLocation
    minimumIndex=Math.max(0,@deletions)
    maximumIndex=Math.min(@data.length-1,@insertions)

    for index in [minimumIndex..maximumIndex]
      currentObject = @data[index][1]
      if @objectEquals(currentObject,obj)
        currentObject[@indexField]=index 
        return index
    return -1

  getNewLocationsForObject : (top,bottom,obj) ->
    objectIndex = @getObjectLocation(obj.annotation)
    currentIndex = objectIndex-1
    currentNewTop = top
    currentNewBottom = bottom
    locationChanges=[]
    # get preceding objects that need to be moved
    while currentIndex>=0
      currentObject=@data[currentIndex][1][@marginobjfield]
      currentObjectBottom=$(currentObject).offset().top+$(currentObject).outerHeight(true)
      if currentObjectBottom>currentNewTop
        objectNewTop=currentNewTop-$(currentObject).outerHeight(true)
        locationChanges.push([objectNewTop,currentObject])
        currentNewTop=objectNewTop
      else
        break
      currentIndex-=1
    # get succeeding objects that need to be moved
    currentIndex = objectIndex+1
    while currentIndex<@data.length
      currentObject=@data[currentIndex][1][@marginobjfield]
      currentObjectTop=$(currentObject).offset().top
      if currentObjectTop<currentNewBottom
        objectNewTop=currentNewBottom
        locationChanges.push([objectNewTop,currentObject])
        currentNewBottom=objectNewTop+$(currentObject).outerHeight(true)
      else
        break
      currentIndex+=1
    return locationChanges

  # binary search
  findIndexForNewObject : (location) ->
    startIndex=0
    endIndex=@data.length
    while startIndex<endIndex
      currentIndex=Math.floor((startIndex+endIndex)/2)
      if @funcObject.sortComparison(location,@data[currentIndex][0])>0
        startIndex=currentIndex+1
      else
        endIndex=currentIndex
    return startIndex

  addNewObject : (obj,topval,leftval) ->
    location={top:topval,left:leftval}
    newObjectLocation=@findIndexForNewObject(location)
    if newObjectLocation>0
      @data=@data[0..newObjectLocation-1].concat([@funcObject.mapFunc(obj)],@data[newObjectLocation..@data.length-1])
    else
      @data=[@funcObject.mapFunc(obj)].concat(@data[newObjectLocation..@data.length-1])
    obj[@indexfield]=newObjectLocation
    @insertions+=1
    
  deleteObject : (object) ->
    objectLocation=@getObjectLocation(object)
    if objectLocation>0
      @data=@data[0..objectLocation-1].concat(@data[objectLocation..@data.length-1])
    else
      @data=@data[1..@data.length-1]
    @deletions+=1

class Annotator.Plugin.MarginViewer extends Annotator.Plugin
  constructor : (element,options) ->
    super
    # TODO: get id of div for margin objects from options

  events:
    'annotationsLoaded':    'onAnnotationsLoaded'      
    'annotationCreated':    'onAnnotationCreated'      
    'annotationDeleted':    'onAnnotationDeleted'      
    'annotationUpdated':    'onAnnotationUpdated'      
    ".annotator-hl click":  "onAnnotationSelected"
            
  pluginInit: ->
    return unless Annotator.supported()
    @annotator.viewer =
      on: ->
      hide: -> 
      load: ->
      isShown: ->
      element: 
        position: ->
        css: ->

    RTL_MULT = -1 #should be -1 if RTL else 1
    sign = (x) ->
      if(x is 0)
        return 0
      else
        return x/Math.abs(x)
    @funcObject =
      sortDataMap: (annotation) ->
        dbg = {top:$(annotation.highlights[0]).offset().top,left:$(annotation.highlights[0]).offset().left}
        return dbg 
      sortComparison : (left,right) -> 
        return sign(sign(left.top - right.top)*2 + sign(left.left - right.left)*RTL_MULT) 
      idFunction : (annotation) -> annotation.id
      sizeFunction : (element) -> element.outerHeight(true)
    @marginData = new Annotator.Plugin.MarginViewerObjectStore [],@funcObject
    
  onAnnotationsLoaded: (annotations) ->
    @marginData = new Annotator.Plugin.MarginViewerObjectStore annotations,@funcObject
    if annotations.length>0
      currentLocation = 0
      for annotation in @marginData.getMarginObjects()
        annotationStart = annotation.highlights[0]
        newLocation = $(annotationStart).offset().top;
        if currentLocation>newLocation
          newLocation=currentLocation
        marginObject=@createMarginObject(annotation,newLocation)
        @marginData.updateObjectLocation(annotation)
        currentLocation = $(marginObject).offset().top+$(marginObject).outerHeight(true)

  onAnnotationCreated: (annotation) ->
    marginObject=@createMarginObject(annotation,hide=true)
    newObjectTop=$(annotation.highlights[0]).offset().top
    newObjectBottom=newObjectTop+$(marginObject).outerHeight(true)
    @marginData.addNewObject(annotation,newObjectTop,$(annotation.highlights[0]).offset().left)
    newLocations=@marginData.getNewLocationsForObject(newObjectTop,newObjectBottom,marginObject)
    @moveObjectsToNewLocation(newLocations)
    $(marginObject).fadeIn('fast').offset({top:newObjectTop})

  onAnnotationSelected: (event) ->
    annotations = $(event.target)
      .parents('.annotator-hl')
      .andSelf()
      .map -> return $(this).data("annotation")
    @onMarginSelected(annotations[0]._marginObject)
 
  onAnnotationDeleted: (annotation) ->
    marginObject=annotation._marginObject
    @marginData.deleteObject(annotation)
    $(marginObject).remove()
    this.publish('delete',annotation)
    
  deleteHandler : (event) ->
    @onAnnotationDeleted(event.target.annotation)

  createMarginObject : (annotation, location=null, hide=false) ->
    marginObjects=$('<div class="annotator-marginviewer-element">'+annotation.text+'</div>').appendTo('.secondary').click((event) => @onMarginSelected(event.target))
    if location!=null
      marginObjects.offset({top: location})
    if hide
      marginObjects.hide()
    marginObject=marginObjects[0]
    annotation._marginObject=marginObject
    marginObject.annotation=annotation
    return marginObject

  onAnnotationUpdated: (annotation) ->
    # updates not supported right now

  onMarginSelected: (marginObject) ->
    annotation = marginObject.annotation
    newTop = $(annotation.highlights[0]).offset().top
    newBottom = $(marginObject).outerHeight(true)+newTop
    newLocationsByObject = @marginData.getNewLocationsForObject(newTop,newBottom,marginObject)
    newLocationsByObject.push([newTop,marginObject])
    @moveObjectsToNewLocation(newLocationsByObject)

  moveObjectsToNewLocation: (newLocations) ->
    for newLocationStructure in newLocations
      newTop = newLocationStructure[0]
      currentObject = newLocationStructure[1]
      $(currentObject).animate({top:"+="+(newTop-$(currentObject).offset().top)},'fast','swing')
      @marginData.updateObjectLocation(currentObject.annotation)

