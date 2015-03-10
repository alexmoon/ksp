PLOT_WIDTH = 300
PLOT_HEIGHT = 300
PLOT_X_OFFSET = 70
TIC_LENGTH = 5

PALETTE = []
PALETTE.push([64, i, 255]) for i in [64...69]
PALETTE.push([128, i, 255]) for i in [133..255]
PALETTE.push([128, 255, i]) for i in [255..128]
PALETTE.push([i, 255, 128]) for i in [128..255]
PALETTE.push([255, i, 128]) for i in [255..128]

class PorkchopPlot
  constructor: (@container) ->
    @canvas = $('canvas', @container)
    @canvasContext = @canvas[0].getContext('2d')
    @progressContainer = $('.progressContainer')
    @plotImageData = @canvasContext.createImageData(PLOT_WIDTH, PLOT_HEIGHT)
    prepareCanvas.call(@)
    
    @mission = null
    @deltaVs = null
    @selectedPoint = null
    
    @dragStart = null
    @dragTouchIdentifier = null
    @dragged = false
    
    @worker = new Worker("javascripts/porkchopworker.js")
    @worker.onmessage = (event) => workerMessage.call(@, event)
    
    $(KerbalTime).on 'dateFormatChanged', (event) => @drawAxisLabels() if @mission?
    
    $('.zoomInBtn', @container).click (event) => @zoomIn()
    $('.zoomOutBtn', @container).click (event) => @zoomOut()
    
    @canvas
      .mousemove (event) =>
        if @deltaVs? and !@dragStart?
          offsetX = event.offsetX ? (event.pageX - @canvas.offset().left) | 0
          offsetY = event.offsetY ? (event.pageY - @canvas.offset().top) | 0
          x = offsetX - PLOT_X_OFFSET
          y = offsetY
          pointer = { x: x, y: ((PLOT_HEIGHT-1) - y) } if x >= 0 and x < PLOT_WIDTH and y < PLOT_HEIGHT
          drawPlot.call(@, pointer)
          
      .mouseleave (event) =>
        drawPlot.call(@) unless @dragStart?
      
      .mousedown (event) =>
        startPanning.call(@, event.pageX, event.pageY) if event.which == 1
        
      .on 'touchstart', (event) =>
        if event.originalEvent.touches.length == 1
          touch = event.originalEvent.touches[0]
          if startPanning.call(@, touch.pageX, touch.pageY, touch.identifier)
            event.preventDefault()

    $(document)
      .on 'mousemove', (event) =>
        panTo.call(@, event.pageX, event.pageY) if @dragStart?
      
      .on 'touchmove', (event) =>
        if @dragStart?
          for touch in event.originalEvent.changedTouches when touch.identifier == @dragTouchIdentifier
            event.preventDefault()
            panTo.call(@, touch.pageX, touch.pageY)
    
      .on 'mouseup', (event) =>
        stopPanning.call(@, event.pageX, event.pageY, true) if event.which == 1 and @dragStart?
      
      .on 'touchcancel touchend', (event) =>
        if @dragStart?
          for touch in event.originalEvent.changedTouches when touch.identifier == @dragTouchIdentifier
            event.preventDefault()
            stopPanning.call(@, touch.pageX, touch.pageY, false)
  
  calculate: (@mission, erase = false) ->
    @mission.xResolution = @mission.xScale / PLOT_WIDTH
    @mission.yResolution = @mission.yScale / PLOT_WIDTH
    
    ctx = @canvasContext
    ctx.clearRect(PLOT_X_OFFSET, 0, PLOT_WIDTH, PLOT_HEIGHT) if erase
    ctx.clearRect(PLOT_X_OFFSET + PLOT_WIDTH + 85, 0, 95, PLOT_HEIGHT + 10)
    
    @drawAxisLabels()
    
    @deltaVs = null
    @selectedPoint = null
    @worker.postMessage(@mission)
    
    $('#porkchopContainer button').prop('disabled', true)
    $(@).trigger('plotStarted')
  
  zoomIn: ->
    xCenter = @mission.earliestDeparture + @selectedPoint.x * @mission.xResolution
    yCenter = @mission.shortestTimeOfFlight + @selectedPoint.y * @mission.yResolution
    @mission.xScale /= Math.sqrt(2)
    @mission.yScale /= Math.sqrt(2)
    @mission.earliestDeparture = Math.max(xCenter - @mission.xScale / 2, 0)
    @mission.shortestTimeOfFlight = Math.max(yCenter - @mission.yScale / 2, 1)
    
    @calculate(@mission)
  
  zoomOut: ->
    xCenter = @mission.earliestDeparture + @selectedPoint.x * @mission.xResolution
    yCenter = @mission.shortestTimeOfFlight + @selectedPoint.y * @mission.yResolution
    @mission.xScale *= Math.sqrt(2)
    @mission.yScale *= Math.sqrt(2)
    earliestDeparture = Math.max(xCenter - @mission.xScale / 2, 0)
    shortestTimeOfFlight = Math.max(yCenter - @mission.yScale / 2, 1)
    
    @calculate(@mission)
    
  # Internal methods
  workerMessage = (event) ->
    if 'log' of event.data
      console.log(event.data.log...)
    else if 'progress' of event.data
      @progressContainer.show().find('.progress-bar').width((event.data.progress * 100 | 0) + "%")
    else if 'deltaVs' of event.data
      @progressContainer.hide().find('.progress-bar').width("0%")
      @deltaVs = event.data.deltaVs
      @deltaVs = new Float64Array(@deltaVs) if @deltaVs instanceof ArrayBuffer
      logMinDeltaV = Math.log(event.data.minDeltaV)
      mean = event.data.sumLogDeltaV / event.data.deltaVCount
      stddev = Math.sqrt(event.data.sumSqLogDeltaV / event.data.deltaVCount - mean * mean)
      logMaxDeltaV = Math.min(Math.log(event.data.maxDeltaV), mean + 2 * stddev)
  
      i = 0
      j = 0
      for y in [0...PLOT_HEIGHT]
        for x in [0...PLOT_WIDTH]
          logDeltaV = Math.log(@deltaVs[i++])
          if isNaN(logDeltaV)
            color = [255, 255, 255]
          else
            relativeDeltaV = if isNaN(logDeltaV) then 1.0 else (logDeltaV - logMinDeltaV) / (logMaxDeltaV - logMinDeltaV)
            colorIndex = Math.min(relativeDeltaV * PALETTE.length | 0, PALETTE.length - 1)
            color = PALETTE[colorIndex]
          @plotImageData.data[j++] = color[0]
          @plotImageData.data[j++] = color[1]
          @plotImageData.data[j++] = color[2]
          @plotImageData.data[j++] = 255
  
      drawDeltaVScale.call(@, logMinDeltaV, logMaxDeltaV)
      @selectedPoint = event.data.minDeltaVPoint
      drawPlot.call(@)
    
      $('#porkchopContainer button').prop('disabled', false)
      $(@).trigger("plotComplete")

  prepareCanvas = ->
    ctx = @canvasContext

    ctx.save()
    ctx.lineWidth = 2
    ctx.strokeStyle = 'black'

    # Draw axes
    ctx.beginPath()
    ctx.moveTo(PLOT_X_OFFSET - 1, 0)
    ctx.lineTo(PLOT_X_OFFSET - 1, PLOT_HEIGHT + 1)
    ctx.lineTo(PLOT_X_OFFSET + PLOT_WIDTH, PLOT_HEIGHT + 1)
    ctx.stroke()

    # Draw tic marks
    ctx.beginPath()
    for i in [0..1.0] by 0.25
      y = PLOT_HEIGHT * i + 1
      ctx.moveTo(PLOT_X_OFFSET - 1, y)
      ctx.lineTo(PLOT_X_OFFSET - 1 - TIC_LENGTH, y)
  
      x = PLOT_X_OFFSET - 1 + PLOT_WIDTH * i
      ctx.moveTo(x, PLOT_HEIGHT + 1)
      ctx.lineTo(x, PLOT_HEIGHT + 1 + TIC_LENGTH)
    ctx.stroke()

    # Draw minor tic marks
    ctx.lineWidth = 0.5
    ctx.beginPath()
    for i in [0..1.0] by 0.05
      continue if i % 0.25 == 0
      y = PLOT_HEIGHT * i + 1
      ctx.moveTo(PLOT_X_OFFSET - 1, y)
      ctx.lineTo(PLOT_X_OFFSET - 1 - TIC_LENGTH, y)
  
      x = PLOT_X_OFFSET - 1 + PLOT_WIDTH * i
      ctx.moveTo(x, PLOT_HEIGHT + 1)
      ctx.lineTo(x, PLOT_HEIGHT + 1 + TIC_LENGTH)
    ctx.stroke()

    # Draw axis titles
    ctx.font = 'italic 12pt "Helvetic Neue",Helvetica,Arial,sans serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillStyle = 'black'
    ctx.fillText("Departure Date (days from epoch)", PLOT_X_OFFSET + PLOT_WIDTH / 2, PLOT_HEIGHT + 40)
    ctx.save()
    ctx.rotate(-Math.PI / 2)
    ctx.textBaseline = 'top'
    ctx.fillText("Time of Flight (days)", -PLOT_HEIGHT / 2, 0)
    ctx.restore()

    # Draw palette key
    paletteKey = ctx.createImageData(20, PLOT_HEIGHT)
    i = 0
    for y in [0...PLOT_HEIGHT]
      j = ((PLOT_HEIGHT - y - 1) * PALETTE.length / PLOT_HEIGHT) | 0
      for x in [0...20]
        paletteKey.data[i++] = PALETTE[j][0]
        paletteKey.data[i++] = PALETTE[j][1]
        paletteKey.data[i++] = PALETTE[j][2]
        paletteKey.data[i++] = 255

    ctx.putImageData(paletteKey, PLOT_X_OFFSET + PLOT_WIDTH + 60, 0)
    ctx.fillText(String.fromCharCode(0x2206) + "v", PLOT_X_OFFSET + PLOT_WIDTH + 45, PLOT_HEIGHT / 2)

    ctx.restore()

  drawAxisLabels: ->
    ctx = @canvasContext
    ctx.save()
    
    ctx.clearRect(20, 0, PLOT_X_OFFSET - TIC_LENGTH - 21, PLOT_HEIGHT + TIC_LENGTH)
    ctx.clearRect(PLOT_X_OFFSET - 40, PLOT_HEIGHT + TIC_LENGTH, PLOT_WIDTH + 80, 20)
  
    ctx.font = '10pt "Helvetic Neue",Helvetica,Arial,sans serif'
    ctx.fillStyle = 'black'
    ctx.textAlign = 'right'
    ctx.textBaseline = 'middle'
    for i in [0..1.0] by 0.25
      ctx.textBaseline = 'top' if i == 1.0
      ctx.fillText(((@mission.shortestTimeOfFlight + i * @mission.yScale) / KerbalTime.secondsPerDay()) | 0, PLOT_X_OFFSET - TIC_LENGTH - 3, (1.0 - i) * PLOT_HEIGHT)
    ctx.textAlign = 'center'
    for i in [0..1.0] by 0.25
      ctx.fillText(((@mission.earliestDeparture + i * @mission.xScale) / KerbalTime.secondsPerDay()) | 0, PLOT_X_OFFSET + i * PLOT_WIDTH, PLOT_HEIGHT + TIC_LENGTH + 3)
    
    ctx.restore()
    
  drawDeltaVScale = (logMinDeltaV, logMaxDeltaV) ->
    ctx = @canvasContext
    ctx.save()
    ctx.font = '10pt "Helvetic Neue",Helvetica,Arial,sans serif'
    ctx.textAlign = 'left'
    ctx.fillStyle = 'black'
    ctx.textBaseline = 'alphabetic'
    for i in [0...1.0] by 0.25
      deltaV = Math.exp(i * (logMaxDeltaV - logMinDeltaV) + logMinDeltaV)
      if deltaV.toFixed().length > 6 then deltaV = deltaV.toExponential(3) else deltaV = deltaV.toFixed()
      ctx.fillText(deltaV + " m/s", PLOT_X_OFFSET + PLOT_WIDTH + 85, (1.0 - i) * PLOT_HEIGHT)
      ctx.textBaseline = 'middle'
    ctx.textBaseline = 'top'
    deltaV = Math.exp(logMaxDeltaV)
    if deltaV.toFixed().length > 6 then deltaV = deltaV.toExponential(3) else deltaV = deltaV.toFixed()
    ctx.fillText(deltaV + " m/s", PLOT_X_OFFSET + PLOT_WIDTH + 85, 0)
    ctx.restore()

  drawPlot = (pointer) ->
    if @deltaVs?
      ctx = @canvasContext
      ctx.save()

      ctx.putImageData(@plotImageData, PLOT_X_OFFSET, 0)

      ctx.lineWidth = 1

      if @selectedPoint?
        x = @selectedPoint.x
        y = @selectedPoint.y
  
        ctx.beginPath()
        if pointer?.x != x
          ctx.moveTo(PLOT_X_OFFSET + x, 0)
          ctx.lineTo(PLOT_X_OFFSET + x, PLOT_HEIGHT)
        if pointer?.y != y
          ctx.moveTo(PLOT_X_OFFSET, (PLOT_HEIGHT-1) - y)
          ctx.lineTo(PLOT_X_OFFSET + PLOT_WIDTH, (PLOT_HEIGHT-1) - y)
        ctx.strokeStyle = 'rgba(0,0,0,0.5)'
        ctx.stroke()

      if pointer?
        x = pointer.x
        y = pointer.y
  
        ctx.beginPath()
        ctx.moveTo(PLOT_X_OFFSET + x, 0)
        ctx.lineTo(PLOT_X_OFFSET + x, PLOT_HEIGHT)
        ctx.moveTo(PLOT_X_OFFSET, (PLOT_HEIGHT-1) - y)
        ctx.lineTo(PLOT_X_OFFSET + PLOT_WIDTH, (PLOT_HEIGHT-1) - y)
        ctx.strokeStyle = 'rgba(255,255,255,0.75)'
        ctx.stroke()
  
        deltaV = @deltaVs[(((PLOT_HEIGHT-1) - y) * PLOT_WIDTH + x) | 0]
        unless isNaN(deltaV)
          tip = " " + String.fromCharCode(0x2206) + "v = " + deltaV.toFixed() + " m/s "
          ctx.font = '10pt "Helvetic Neue",Helvetica,Arial,sans serif'
          ctx.fillStyle = 'black'
          ctx.textAlign = if x < PLOT_WIDTH / 2 then 'left' else 'right'
          ctx.textBaseline = if y < PLOT_HEIGHT - 16 then 'bottom' else 'top'
          ctx.fillText(tip, x + PLOT_X_OFFSET, (PLOT_HEIGHT-1) - y)
  
      ctx.restore()

  startPanning = (pageX, pageY, touchIdentifier = null) ->
    if @deltaVs?
      offsetX = (pageX - @canvas.offset().left) | 0
      offsetY = (pageY - @canvas.offset().top) | 0
      if offsetX >= PLOT_X_OFFSET and offsetX < (PLOT_X_OFFSET + PLOT_WIDTH) and offsetY < PLOT_HEIGHT
        @dragTouchIdentifier = touchIdentifier
        @dragStart = { x: pageX, y: pageY }

  panTo = (pageX, pageY) ->
    @dragged = true
    ctx = @canvasContext
    ctx.clearRect(PLOT_X_OFFSET, 0, PLOT_WIDTH, PLOT_HEIGHT)

    deltaX = pageX - @dragStart.x
    if deltaX > (@mission.earliestDeparture) / @mission.xResolution
      deltaX = (@mission.earliestDeparture) / @mission.xResolution
      @dragStart.x = pageX - deltaX
    deltaY = pageY - @dragStart.y
    if deltaY < (1 - @mission.shortestTimeOfFlight) / @mission.yResolution
      deltaY = (1 - @mission.shortestTimeOfFlight) / @mission.yResolution
      @dragStart.y = pageY - deltaY
    dirtyX = Math.max(-deltaX, 0)
    dirtyY = Math.max(-deltaY, 0)
    dirtyWidth = PLOT_WIDTH - Math.abs(deltaX)
    dirtyHeight = PLOT_HEIGHT - Math.abs(deltaY)
    ctx.putImageData(@plotImageData, PLOT_X_OFFSET + deltaX, deltaY, dirtyX, dirtyY, dirtyWidth, dirtyHeight)
  
  stopPanning = (pageX, pageY, showPointer) ->
    @canvas.removeClass('grabbing')
    if @dragged
      if @dragStart.x != pageX or @dragStart.y != pageY
        # Drag end
        deltaX = pageX - @dragStart.x
        deltaY = pageY - @dragStart.y
        @mission.earliestDeparture = Math.max(@mission.earliestDeparture - deltaX * @mission.xResolution, 0)
        @mission.shortestTimeOfFlight = Math.max(@mission.shortestTimeOfFlight + deltaY * @mission.yResolution, 1)
        @calculate(@mission)
      else
        drawPlot.call(@)
    else
      # Click, select new transfer
      offsetX = (pageX - @canvas.offset().left) | 0
      offsetY = (pageY - @canvas.offset().top) | 0
      x = offsetX - PLOT_X_OFFSET
      y = offsetY
    
      if x >= 0 and x < PLOT_WIDTH and y < PLOT_HEIGHT and !isNaN(@deltaVs[(y * PLOT_WIDTH + x) | 0])
        @selectedPoint = { x: x, y: (PLOT_HEIGHT-1) - y }
        drawPlot.call(@, @selectedPoint if showPointer)
        $(@).trigger('click', @selectedPoint)

    @dragStart = null
    @dragTouchIdentifier = null
    @dragged = false
  

(exports ? this).PorkchopPlot = PorkchopPlot
