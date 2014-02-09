PLOT_WIDTH = 300
PLOT_HEIGHT = 300
PLOT_X_OFFSET = 70
TIC_LENGTH = 5

transferType = null
originBody = null
destinationBody = null
initialOrbitalVelocity = null
finalOrbitalVelocity = null
earliestDeparture = null
shortestTimeOfFlight = null
xScale = null
yScale = null
deltaVs = null

canvasContext = null
plotImageData = null
selectedPoint = null
selectedTransfer = null

palette = []
palette.push([64, i, 255]) for i in [64...69]
palette.push([128, i, 255]) for i in [133..255]
palette.push([128, 255, i]) for i in [255..128]
palette.push([i, 255, 128]) for i in [128..255]
palette.push([255, i, 128]) for i in [255..128]

clamp = (n, min, max) -> Math.max(min, Math.min(n, max))

sign = (x) -> if x < 0 then -1 else 1

isBlank = (str) -> !/\S/.test(str)

numberWithCommas = (n) ->
  n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")

hourMinSec = (t) ->
  hour = (t / 3600) | 0
  t %= 3600
  min = (t / 60) | 0
  min = "0#{min}" if min < 10
  sec = (t % 60).toFixed()
  sec = "0#{sec}" if sec < 10
  "#{hour}:#{min}:#{sec}"
  
kerbalDateString = (t) ->
  year = ((t / (365 * 24 * 3600)) | 0) + 1
  t %= (365 * 24 * 3600)
  day = ((t / (24 * 3600)) | 0) + 1
  t %= (24 * 3600)
  "Year #{year}, day #{day} at #{hourMinSec(t)}"

durationString = (t) ->
  result = ""
  if t >= 365 * 24 * 3600
    result += (t / (365 * 24 * 3600) | 0) + " years "
    t %= 365 * 24 * 3600
    result += "0 days " if t < 24 * 3600
  result += (t / (24 * 3600) | 0) + " days " if t >= 24 * 3600
  t %= 24 * 3600
  result + hourMinSec(t)

distanceString = (d) ->
  if Math.abs(d) > 1e12
    numberWithCommas((d / 1e9).toFixed()) + " Gm"
  else if Math.abs(d) >= 1e9
    numberWithCommas((d / 1e6).toFixed()) + " Mm"
  else if Math.abs(d) >= 1e6
    numberWithCommas((d / 1e3).toFixed()) + " km"
  else
    numberWithCommas(d.toFixed()) + " m"

deltaVAbbr = (el, dv, prograde, normal, radial) ->
  tooltip = numberWithCommas(prograde.toFixed(1)) + " m/s prograde; " +
    numberWithCommas(normal.toFixed(1)) + " m/s normal"
  tooltip += "; " + numberWithCommas(radial.toFixed(1)) + " m/s radial" if radial?
  el.attr(title: tooltip).text(numberWithCommas(dv.toFixed()) + " m/s")
  
angleString = (angle, precision = 0) ->
  (angle * 180 / Math.PI).toFixed(precision) + String.fromCharCode(0x00b0)

shortKerbalDateString = (t) ->
  year = ((t / (365 * 24 * 3600)) | 0) + 1
  t %= (365 * 24 * 3600)
  day = ((t / (24 * 3600)) | 0) + 1
  t %= (24 * 3600)
  "#{year}/#{day} #{hourMinSec(t)}"

dateFromString = (dateString) ->
  componentScales = [365, 24, 60, 60]
  
  components = dateString.match(/(\d+)\/(\d+)\s+(\d+):(\d+):(\d+)/)
  components.shift()
  components = components.reverse()
  
  time = 0
  scale = 1
  for c in components
    c = c - 1 if scale > 3600
    time += scale * c
    break if componentScales.length == 0
    scale *= componentScales.pop()
  time

worker = new Worker("javascripts/porkchopworker.js")

worker.onmessage = (event) ->
  if 'progress' of event.data
    $('#porkchopProgress').show().find('.progress-bar').width((event.data.progress * 100 | 0) + "%")
  else if 'deltaVs' of event.data
    $('#porkchopProgress').hide().find('.progress-bar').width("0%")
    deltaVs = event.data.deltaVs
    deltaVs = new Float64Array(deltaVs) if deltaVs instanceof ArrayBuffer
    minDeltaV = event.data.minDeltaV
    maxDeltaV = 4 * minDeltaV
    
    i = 0
    j = 0
    for y in [0...PLOT_HEIGHT]
      for x in [0...PLOT_WIDTH]
        deltaV = deltaVs[i++]
        relativeDeltaV = if isNaN(deltaV) then 1.0 else (clamp(deltaV, minDeltaV, maxDeltaV) - minDeltaV) / (maxDeltaV - minDeltaV)
        colorIndex = Math.min(relativeDeltaV * palette.length | 0, palette.length - 1)
        color = palette[colorIndex]
        plotImageData.data[j++] = color[0]
        plotImageData.data[j++] = color[1]
        plotImageData.data[j++] = color[2]
        plotImageData.data[j++] = 255
    
    drawDeltaVScale(minDeltaV, maxDeltaV)
    showTransferDetailsForPoint(event.data.minDeltaVPoint)
    drawPlot()
    
    $('#porkchopSubmit,#porkchopContainer button,#refineTransferBtn').prop('disabled', false)

calculatePlot = (erasePlot) ->
  ctx = canvasContext
  ctx.clearRect(PLOT_X_OFFSET, 0, PLOT_WIDTH, PLOT_HEIGHT) if erasePlot
  ctx.clearRect(PLOT_X_OFFSET + PLOT_WIDTH + 85, 0, 65, PLOT_HEIGHT + 10)
  ctx.clearRect(20, 0, PLOT_X_OFFSET - TIC_LENGTH - 21, PLOT_HEIGHT + TIC_LENGTH)
  ctx.clearRect(PLOT_X_OFFSET - 40, PLOT_HEIGHT + TIC_LENGTH, PLOT_WIDTH + 80, 20)
  
  ctx.font = '10pt "Helvetic Neue",Helvetica,Arial,sans serif'
  ctx.fillStyle = 'black'
  ctx.textAlign = 'right'
  ctx.textBaseline = 'middle'
  for i in [0..1.0] by 0.25
    ctx.textBaseline = 'top' if i == 1.0
    ctx.fillText(((shortestTimeOfFlight + i * yScale) / 3600 / 24) | 0, PLOT_X_OFFSET - TIC_LENGTH - 3, (1.0 - i) * PLOT_HEIGHT)
  ctx.textAlign = 'center'
  for i in [0..1.0] by 0.25
    ctx.fillText(((earliestDeparture + i * xScale) / 3600 / 24) | 0, PLOT_X_OFFSET + i * PLOT_WIDTH, PLOT_HEIGHT + TIC_LENGTH + 3)
    
  deltaVs = null
  worker.postMessage(
    transferType: transferType, originBody: originBody, destinationBody: destinationBody,
    initialOrbitalVelocity: initialOrbitalVelocity, finalOrbitalVelocity: finalOrbitalVelocity,
    earliestDeparture: earliestDeparture, xScale: xScale,
    shortestTimeOfFlight: shortestTimeOfFlight, yScale: yScale)
  
drawDeltaVScale = (minDeltaV, maxDeltaV) ->
  ctx = canvasContext
  ctx.save()
  ctx.font = '10pt "Helvetic Neue",Helvetica,Arial,sans serif'
  ctx.textAlign = 'left'
  ctx.fillStyle = 'black'
  ctx.textBaseline = 'alphabetic'
  for i in [0...1.0] by 0.25
    ctx.fillText((minDeltaV + i * (maxDeltaV - minDeltaV)).toFixed() + " m/s", PLOT_X_OFFSET + PLOT_WIDTH + 85, (1.0 - i) * PLOT_HEIGHT)
    ctx.textBaseline = 'middle'
  ctx.textBaseline = 'top'
  ctx.fillText(maxDeltaV.toFixed() + " m/s", PLOT_X_OFFSET + PLOT_WIDTH + 85, 0)
  ctx.restore()
  
drawPlot = (pointer) ->
  if deltaVs?
    ctx = canvasContext
    ctx.save()
  
    ctx.putImageData(plotImageData, PLOT_X_OFFSET, 0)
  
    ctx.lineWidth = 1
  
    if selectedPoint?
      x = selectedPoint.x
      y = selectedPoint.y
    
      ctx.beginPath()
      if pointer?.x != x
        ctx.moveTo(PLOT_X_OFFSET + x, 0)
        ctx.lineTo(PLOT_X_OFFSET + x, PLOT_HEIGHT)
      if pointer?.y != y
        ctx.moveTo(PLOT_X_OFFSET, y)
        ctx.lineTo(PLOT_X_OFFSET + PLOT_WIDTH, y)
      ctx.strokeStyle = 'rgba(0,0,0,0.5)'
      ctx.stroke()

    if pointer?
      x = pointer.x
      y = pointer.y
    
      ctx.beginPath()
      ctx.moveTo(PLOT_X_OFFSET + x, 0)
      ctx.lineTo(PLOT_X_OFFSET + x, PLOT_HEIGHT)
      ctx.moveTo(PLOT_X_OFFSET, y)
      ctx.lineTo(PLOT_X_OFFSET + PLOT_WIDTH, y)
      ctx.strokeStyle = 'rgba(255,255,255,0.75)'
      ctx.stroke()
    
      deltaV = deltaVs[(y * PLOT_WIDTH + x) | 0]
      unless isNaN(deltaV)
        tip = " " + String.fromCharCode(0x2206) + "v = " + deltaV.toFixed() + " m/s "
        ctx.font = '10pt "Helvetic Neue",Helvetica,Arial,sans serif'
        ctx.fillStyle = 'black'
        ctx.textAlign = if x < PLOT_WIDTH / 2 then 'left' else 'right'
        ctx.textBaseline = if y > 15 then 'bottom' else 'top'
        ctx.fillText(tip, x + PLOT_X_OFFSET, y)
    
    ctx.restore()

prepareCanvas = ->
  ctx = canvasContext
  
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
    j = ((PLOT_HEIGHT - y - 1) * palette.length / PLOT_HEIGHT) | 0
    for x in [0...20]
      paletteKey.data[i++] = palette[j][0]
      paletteKey.data[i++] = palette[j][1]
      paletteKey.data[i++] = palette[j][2]
      paletteKey.data[i++] = 255
  
  ctx.putImageData(paletteKey, PLOT_X_OFFSET + PLOT_WIDTH + 60, 0)
  ctx.fillText(String.fromCharCode(0x2206) + "v", PLOT_X_OFFSET + PLOT_WIDTH + 45, PLOT_HEIGHT / 2)
  
  ctx.restore()

showTransferDetailsForPoint = (point) ->
  selectedPoint = point
  
  [x, y] = [point.x, point.y]
  t0 = earliestDeparture + x * xScale / PLOT_WIDTH
  dt = shortestTimeOfFlight + ((PLOT_HEIGHT-1) - y) * yScale / PLOT_HEIGHT
  
  transfer = Orbit.transfer(transferType, originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity)
  showTransferDetails(transfer, t0, dt)
  
showTransferDetails = (transfer, t0, dt) ->
  t1 = t0 + dt
  transfer = Orbit.transferDetails(transfer, originBody, t0, initialOrbitalVelocity)
  selectedTransfer = transfer

  originOrbit = originBody.orbit
  destinationOrbit = destinationBody.orbit
  
  $('#departureTime').text(kerbalDateString(t0)).attr(title: "UT: #{t0.toFixed()}s")
  $('#arrivalTime').text(kerbalDateString(t1)).attr(title: "UT: #{t1.toFixed()}s")
  $('#timeOfFlight').text(durationString(dt)).attr(title: dt.toFixed() + "s")
  $('#phaseAngle').text(angleString(originOrbit.phaseAngle(destinationOrbit, t0), 2))
  if transfer.ejectionAngle?
    $('.ejectionAngle').show()
    if destinationOrbit.semiMajorAxis < originOrbit.semiMajorAxis
      ejectionAngle = transfer.ejectionAngle - Math.PI
      ejectionAngle += 2 * Math.PI if ejectionAngle < 0
      $('#ejectionAngle').text(angleString(ejectionAngle) + " to retrograde")
    else
      $('#ejectionAngle').text(angleString(transfer.ejectionAngle) + " to prograde")
  else
    $('.ejectionAngle').hide()
  $('#ejectionDeltaV').text(numberWithCommas(transfer.ejectionDeltaV.toFixed()) + " m/s")
  $('#ejectionDeltaVInfo').popover('hide')
  $('#transferPeriapsis').text(distanceString(transfer.orbit.periapsisAltitude()))
  $('#transferApoapsis').text(distanceString(transfer.orbit.apoapsisAltitude()))
  $('#transferInclination').text(angleString(transfer.orbit.inclination, 2))
  $('#transferAngle').text(angleString(transfer.angle))
  
  if transfer.planeChangeTime?
    $('.ballisticTransfer').hide()
    $('.planeChangeTransfer').show()
    $('#planeChangeTime').text(kerbalDateString(transfer.planeChangeTime))
      .attr(title: "UT: #{transfer.planeChangeTime.toFixed()}s")
    $('#planeChangeAngleToIntercept').text(angleString(transfer.planeChangeAngleToIntercept, 2))
    $('#planeChangeAngle').text(angleString(transfer.planeChangeAngle, 2))
    deltaVAbbr($('#planeChangeDeltaV'), transfer.planeChangeDeltaV,
      -transfer.planeChangeDeltaV * Math.abs(Math.sin(transfer.planeChangeAngle / 2)),
      transfer.planeChangeDeltaV * sign(transfer.planeChangeAngle) * Math.cos(transfer.planeChangeAngle / 2))
  else
    $('.planeChangeTransfer').hide()
    $('.ballisticTransfer').show()
    $('#ejectionInclination').text(angleString(transfer.ejectionInclination, 2))
    
  if transfer.insertionInclination?
    $('#insertionInclination').text(angleString(transfer.insertionInclination, 2))
  else
    $('#insertionInclination').text("N/A")
  if transfer.insertionDeltaV != 0
    $('#insertionDeltaV').text(numberWithCommas(transfer.insertionDeltaV.toFixed()) + " m/s")
  else
    $('#insertionDeltaV').text("N/A")
  $('#totalDeltaV').text(numberWithCommas(transfer.deltaV.toFixed()) + " m/s")

  $('#transferDetails:hidden').fadeIn()

updateAdvancedControls = ->
  origin = CelestialBody[$('#originSelect').val()]
  destination = CelestialBody[$('#destinationSelect').val()]
  referenceBody = origin.orbit.referenceBody
  hohmannTransfer = Orbit.fromApoapsisAndPeriapsis(referenceBody, destination.orbit.semiMajorAxis, origin.orbit.semiMajorAxis, 0, 0, 0, 0)
  hohmannTransferTime = hohmannTransfer.period() / 2
  synodicPeriod = Math.abs(1 / (1 / destination.orbit.period() - 1 / origin.orbit.period()))
  
  departureRange = Math.min(2 * synodicPeriod, 2 * origin.orbit.period()) / (24 * 3600)
  if departureRange < 0.1
    departureRange = +departureRange.toFixed(2)
  else if departureRange < 1
    departureRange = +departureRange.toFixed(1)
  else
    departureRange = +departureRange.toFixed()
  minDeparture = ($('#earliestDepartureYear').val() - 1) * 365 + ($('#earliestDepartureDay').val() - 1)
  maxDeparture = minDeparture + departureRange
  
  minDays = Math.max(hohmannTransferTime - destination.orbit.period(), hohmannTransferTime / 2) / 3600 / 24
  maxDays = minDays + Math.min(2 * destination.orbit.period(), hohmannTransferTime) / 3600 / 24
  minDays = if minDays < 10 then minDays.toFixed(2) else minDays.toFixed()
  maxDays = if maxDays < 10 then maxDays.toFixed(2) else maxDays.toFixed()
  
  $('#latestDepartureYear').val((maxDeparture / 365 | 0) + 1)
  $('#latestDepartureDay').val((maxDeparture % 365) + 1)
  $('#shortestTimeOfFlight').val(minDays)
  $('#longestTimeOfFlight').val(maxDays)
  
  $('#finalOrbit').attr("disabled", $('#noInsertionBurnCheckbox').is(":checked")) if destination.mass?

window.prepareOrigins = prepareOrigins = -> # Globalized so bodies can be added in the console
  originSelect = $('#originSelect')
  referenceBodySelect = $('#referenceBodySelect')
  
  # Reset the origin and reference body select boxes
  originSelect .empty()
  referenceBodySelect.empty()
  
  # Add Kerbol to the reference body select box
  $('<option>').text('Kerbol').appendTo(referenceBodySelect)
  
  # Add other all known bodies to both select boxes
  listBody = (referenceBody, originGroup, referenceBodyGroup) ->
    children = Object.keys(referenceBody.children())
    children.sort((a,b) -> CelestialBody[a].orbit.semiMajorAxis - CelestialBody[b].orbit.semiMajorAxis)
    for name in children
      body = CelestialBody[name]
      originGroup.append($('<option>').text(name))
      if body.mass?
        referenceBodyGroup.append($('<option>').text(name))
        listBody(body, originGroup, referenceBodyGroup)
  
  addPlanetGroup = (planet, group, selectBox, minChildren) ->
    if group.children().size() >= minChildren
      group.attr('label', planet + ' System')
        .prepend($('<option>').text(planet))
        .appendTo(selectBox)
    else
      $('<option>').text(planet).appendTo(selectBox)
  
  bodies = Object.keys(CelestialBody.Kerbol.children())
  bodies.sort((a,b) -> CelestialBody[a].orbit.semiMajorAxis - CelestialBody[b].orbit.semiMajorAxis)
  for name in bodies
    body = CelestialBody[name]
    if !body.mass?
      $('<option>').text(name).appendTo(originSelect)
    else
      originGroup = $('<optgroup>')
      referenceBodyGroup = $('<optgroup>')
      
      listBody(body, originGroup, referenceBodyGroup)
      
      addPlanetGroup(name, originGroup, originSelect, 2)
      addPlanetGroup(name, referenceBodyGroup, referenceBodySelect, 1)
  
  # Select Kerbin as the default origin, or the first option if Kerbin is missing
  originSelect.val('Kerbin')
  originSelect.prop('selectedIndex', 0) unless originSelect.val()?

$(document).ready ->
  canvasContext = document.getElementById('porkchopCanvas').getContext('2d')
  plotImageData = canvasContext.createImageData(PLOT_WIDTH, PLOT_HEIGHT)
  
  prepareCanvas()
  prepareOrigins()
  
  porkchopDragStart = null
  porkchopDragTouchIdentifier = null
  porkchopDragged = false
  $('#porkchopCanvas')
    .mousedown (event) ->
      if event.which == 1 and deltaVs?
        offsetX = event.offsetX ? (event.pageX - $('#porkchopCanvas').offset().left) | 0
        offsetY = event.offsetY ? (event.pageY - $('#porkchopCanvas').offset().top) | 0
        if offsetX >= PLOT_X_OFFSET and offsetX < (PLOT_X_OFFSET + PLOT_WIDTH) and offsetY < PLOT_HEIGHT
          $(this).addClass('grabbing')
          porkchopDragStart = { x: event.pageX, y: event.pageY }
          
    .mousemove (event) ->
      if deltaVs? and !porkchopDragStart?
        offsetX = event.offsetX ? (event.pageX - $('#porkchopCanvas').offset().left) | 0
        offsetY = event.offsetY ? (event.pageY - $('#porkchopCanvas').offset().top) | 0
        x = offsetX - PLOT_X_OFFSET
        y = offsetY
        pointer = { x: x, y: y } if x >= 0 and x < PLOT_WIDTH and y < PLOT_HEIGHT
        drawPlot(pointer)
        
    .mouseleave (event) ->
      drawPlot() unless porkchopDragStart?
    
    .on 'touchstart', (event) ->
      if event.originalEvent.touches.length == 1 and deltaVs?
        touch = event.originalEvent.touches[0]
        offsetX = (touch.pageX - $('#porkchopCanvas').offset().left) | 0
        offsetY = (touch.pageY - $('#porkchopCanvas').offset().top) | 0
        if offsetX >= PLOT_X_OFFSET and offsetX < (PLOT_X_OFFSET + PLOT_WIDTH) and offsetY < PLOT_HEIGHT
          event.preventDefault()
          porkchopDragTouchIdentifier = touch.identifier
          porkchopDragStart = { x: touch.pageX, y: touch.pageY }
    
  $(document)
    .on 'mousemove touchmove', (event) ->
      if porkchopDragStart?
        if event.type == 'mousemove'
          pageX = event.pageX
          pageY = event.pageY
        else
          for touch in event.originalEvent.changedTouches
            break if touch.identifier == porkchopDragTouchIdentifier
            
          return unless (touch.identifier == porkchopDragTouchIdentifier)
          
          event.preventDefault()
          pageX = touch.pageX
          pageY = touch.pageY
          
        porkchopDragged = true
        ctx = canvasContext
        ctx.clearRect(PLOT_X_OFFSET, 0, PLOT_WIDTH, PLOT_HEIGHT)
        
        deltaX = pageX - porkchopDragStart.x
        if deltaX > (earliestDeparture * PLOT_WIDTH) / xScale
          deltaX = (earliestDeparture * PLOT_WIDTH) / xScale
          porkchopDragStart.x = pageX - deltaX
        deltaY = pageY - porkchopDragStart.y
        if deltaY < (1 - shortestTimeOfFlight) * PLOT_HEIGHT / yScale
          deltaY = (1 - shortestTimeOfFlight) * PLOT_HEIGHT / yScale
          porkchopDragStart.y = pageY - deltaY
        dirtyX = Math.max(-deltaX, 0)
        dirtyY = Math.max(-deltaY, 0)
        dirtyWidth = PLOT_WIDTH - Math.abs(deltaX)
        dirtyHeight = PLOT_HEIGHT - Math.abs(deltaY)
        ctx.putImageData(plotImageData, PLOT_X_OFFSET + deltaX, deltaY, dirtyX, dirtyY, dirtyWidth, dirtyHeight)
    
    .on 'mouseup touchcancel touchend', (event) ->
      if porkchopDragStart?
        if event.type == 'mouseup'
          return unless event.which == 1
          pageX = event.pageX
          pageY = event.pageY
        else
          for touch in event.originalEvent.changedTouches
            break if touch.identifier == porkchopDragTouchIdentifier
            
          return unless (touch.identifier == porkchopDragTouchIdentifier)
          
          event.preventDefault()
          pageX = touch.pageX
          pageY = touch.pageY
        
        $('#porkchopCanvas').removeClass('grabbing')
        if porkchopDragged
          if porkchopDragStart.x != pageX or porkchopDragStart.y != pageY
            # Drag end
            deltaX = pageX - porkchopDragStart.x
            deltaY = pageY - porkchopDragStart.y
            earliestDeparture = Math.max(earliestDeparture - deltaX * xScale / PLOT_WIDTH, 0)
            shortestTimeOfFlight = Math.max(shortestTimeOfFlight + deltaY * yScale / PLOT_HEIGHT, 1)
            calculatePlot()
          else
            drawPlot()
        else
          # Click, select new transfer
          offsetX = (pageX - $('#porkchopCanvas').offset().left) | 0
          offsetY = (pageY - $('#porkchopCanvas').offset().top) | 0
          x = offsetX - PLOT_X_OFFSET
          y = offsetY
          if x >= 0 and x < PLOT_WIDTH and y < PLOT_HEIGHT and !isNaN(deltaVs[(y * PLOT_WIDTH + x) | 0])
            showTransferDetailsForPoint(x: x, y: y)
            if event.type == 'mouseup'
              drawPlot(x: x, y: y)
            else
              drawPlot()
            ga('send', 'event', 'porkchop', 'click', "#{x},#{y}")
    
        porkchopDragStart = null
        porkchopDragTouchIdentifier = null
        porkchopDragged = false
  
  $('#porkchopZoomIn').click (event) ->
    xCenter = earliestDeparture + selectedPoint.x * xScale / PLOT_WIDTH
    yCenter = shortestTimeOfFlight + ((PLOT_HEIGHT-1) - selectedPoint.y) * yScale / PLOT_HEIGHT
    xScale /= Math.sqrt(2)
    yScale /= Math.sqrt(2)
    earliestDeparture = Math.max(xCenter - xScale / 2, 0)
    shortestTimeOfFlight = Math.max(yCenter - yScale / 2, 1)
    
    calculatePlot()
  
  $('#porkchopZoomOut').click (event) ->
    xCenter = earliestDeparture + selectedPoint.x * xScale / PLOT_WIDTH
    yCenter = shortestTimeOfFlight + ((PLOT_HEIGHT-1) - selectedPoint.y) * yScale / PLOT_HEIGHT
    xScale *= Math.sqrt(2)
    yScale *= Math.sqrt(2)
    earliestDeparture = Math.max(xCenter - xScale / 2, 0)
    shortestTimeOfFlight = Math.max(yCenter - yScale / 2, 1)
    
    calculatePlot()
  
  $('#refineTransferBtn').click (event) ->
    [x, y] = [selectedPoint.x, selectedPoint.y]
    t0 = earliestDeparture + x * xScale / PLOT_WIDTH
    dt = shortestTimeOfFlight + ((PLOT_HEIGHT-1) - y) * yScale / PLOT_HEIGHT
    
    transfer = Orbit.refineTransfer(selectedTransfer, transferType, originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity)
    showTransferDetails(transfer, t0, dt)
  
  $('.altitude').tooltip(container: 'body')
  
  ejectionDeltaVInfoContent = ->
    list = $("<dl>")
    $("<dt>").text("Prograde \u0394v").appendTo(list)
    $("<dd>").text(numberWithCommas(selectedTransfer.ejectionProgradeDeltaV.toFixed(1)) + " m/s").appendTo(list)
    $("<dt>").text("Normal \u0394v").appendTo(list)
    $("<dd>").text(numberWithCommas(selectedTransfer.ejectionNormalDeltaV.toFixed(1)) + " m/s").appendTo(list)
    
    if selectedTransfer.ejectionRadialDeltaV?
      $("<dt>").text("Radial \u0394v").appendTo(list)
      $("<dd>").text(numberWithCommas(selectedTransfer.ejectionRadialDeltaV.toFixed(1)) + " m/s").appendTo(list)
      
    
    $("<dd>").html("&nbsp;").appendTo(list) # Spacer
    
    if selectedTransfer.ejectionPitch?
      $("<dt>").text("Pitch").appendTo(list)
      $("<dd>").text(angleString(selectedTransfer.ejectionPitch, 2)).appendTo(list)
      
    $("<dt>").text("Heading").appendTo(list)
    $("<dd>").text(angleString(selectedTransfer.ejectionHeading, 2)).appendTo(list)
    
    list
    
  $('#ejectionDeltaVInfo').popover(html: true, content: ejectionDeltaVInfoContent)
    .click((event) -> event.preventDefault()).on 'show.bs.popover', ->
      $(this).next().find('.popover-content').html(ejectionDeltaVInfoContent())
  
  $('#originSelect').change (event) ->
    origin = CelestialBody[$(this).val()]
    referenceBody = origin.orbit.referenceBody
    
    $('#initialOrbit').attr("disabled", !origin.mass?)
    
    s = $('#destinationSelect')
    previousDestination = s.val()
    s.empty()
    bodies = Object.keys(referenceBody.children())
    bodies.sort((a,b) -> CelestialBody[a].orbit.semiMajorAxis - CelestialBody[b].orbit.semiMajorAxis)
    s.append($('<option>').text(name)) for name in bodies when CelestialBody[name] != origin
    s.val(previousDestination)
    s.prop('selectedIndex', 0) unless s.val()?
    s.prop('disabled', s[0].childNodes.length == 0)
    
    updateAdvancedControls()
  
  $('#destinationSelect').change (event) ->
    $('#finalOrbit').attr("disabled", !CelestialBody[$(this).val()].mass?)
    updateAdvancedControls()
    
  $('#originSelect').change()
  $('#destinationSelect').val('Duna')
  $('#destinationSelect').change()
  
  $('#noInsertionBurnCheckbox').change (event) ->
    if CelestialBody[$('#destinationSelect').val()].mass?
      $('#finalOrbit').attr("disabled", $(this).is(":checked"))
  
  $('#showAdvancedControls').click (event) ->
    $this = $(this)
    if $this.text().indexOf('Show') != -1
      $this.text('Hide advanced settings...')
      $('#advancedControls').slideDown()
    else
      $(this).text('Show advanced settings...')
      $('#advancedControls').slideUp()
  
  $('#earliestDepartureYear,#earliestDepartureDay').change (event) ->
    if $('#showAdvancedControls').text().indexOf('Show') != -1
      updateAdvancedControls()
    else
      if +$('#earliestDepartureYear').val() > +$('#latestDepartureYear').val()
        $('#latestDepartureYear').val($('#earliestDepartureYear').val())
        
      if +$('#earliestDepartureYear').val() == +$('#latestDepartureYear').val()
        if +$('#earliestDepartureDay').val() >= +$('#latestDepartureDay').val()
          $('#latestDepartureDay').val(+$('#earliestDepartureDay').val() + 1)
  
  $('#shortestTimeOfFlight,#longestTimeOfFlight').change (event) ->
    if +$('#shortestTimeOfFlight').val() <= 0
      $('#shortestTimeOfFlight').val(1)
    if +$('#longestTimeOfFlight').val() <= 0
      $('#longestTimeOfFlight').val(2)
    if +$('#shortestTimeOfFlight').val() >= $('#longestTimeOfFlight').val()
      if @id == 'shortestTimeOfFlight'
        $('#longestTimeOfFlight').val(+$('#shortestTimeOfFlight').val() + 1)
      else if +$('#longestTimeOfFlight').val() > 1
        $('#shortestTimeOfFlight').val(+$('#longestTimeOfFlight').val() - 1)
      else
        $('#shortestTimeOfFlight').val(+$('#longestTimeOfFlight').val() / 2)
        
  $('#porkchopForm').bind 'reset', (event) ->
    setTimeout(-> 
        $('#originSelect').val('Kerbin')
        $('#originSelect').change()
        $('#destinationSelect').val('Duna')
        $('#destinationSelect').change()
      0)
  
  $('#porkchopForm').submit (event) ->
    event.preventDefault()
    $('#porkchopSubmit,#porkchopContainer button,#refineTransferBtn').prop('disabled', true)
    
    scrollTop = $('#porkchopCanvas').offset().top + $('#porkchopCanvas').height() - $(window).height()
    $("html,body").animate(scrollTop: scrollTop, 500) if $(document).scrollTop() < scrollTop
    
    originBodyName = $('#originSelect').val()
    destinationBodyName = $('#destinationSelect').val()
    initialOrbit = $('#initialOrbit').val().trim()
    finalOrbit = $('#finalOrbit').val().trim()
    transferType = $('#transferTypeSelect').val()
    
    originBody = CelestialBody[originBodyName]
    destinationBody = CelestialBody[destinationBodyName]
    
    if !originBody.mass? or +initialOrbit == 0
      initialOrbitalVelocity = 0
    else
      initialOrbitalVelocity = originBody.circularOrbitVelocity(initialOrbit * 1e3)
        
    if $('#noInsertionBurnCheckbox').is(":checked")
      finalOrbitalVelocity = null
    else if !destinationBody.mass? or +finalOrbit == 0
      finalOrbitalVelocity = 0
    else
      finalOrbitalVelocity = destinationBody.circularOrbitVelocity(finalOrbit * 1e3)
    
    earliestDeparture = ($('#earliestDepartureYear').val() - 1) * 365 + ($('#earliestDepartureDay').val() - 1)
    earliestDeparture *= 24 * 3600
    
    latestDeparture = ($('#latestDepartureYear').val() - 1) * 365 + ($('#latestDepartureDay').val() - 1)
    latestDeparture *= 24 * 3600
    xScale = latestDeparture - earliestDeparture
    
    shortestTimeOfFlight = +$('#shortestTimeOfFlight').val() * 24 * 3600
    yScale = +$('#longestTimeOfFlight').val() * 24 * 3600 - shortestTimeOfFlight
    
    calculatePlot(true)

    description = "#{originBodyName} @#{+initialOrbit}km to #{destinationBodyName}"
    description += " @#{+finalOrbit}km" if finalOrbit
    description += " after day #{earliestDeparture / (24 * 3600)} via #{$('#transferTypeSelect option:selected').text()} transfer"
    ga('send', 'event', 'porkchop', 'submit', description)

  addBodyForm = (referenceBody) ->
    $('#bodyForm .form-group').removeClass('has-error')
    $('#bodyForm .help-block').hide()
    
    $('#bodyType a[href="#planetFields"]').tab('show')
    
    if referenceBody?
      $('#referenceBodySelect').val(referenceBody.name()).prop('disabled', true)
      $('#bodyForm .modal-header h4').text("New destination orbiting #{referenceBody.name()}")
    else
      $('#referenceBodySelect').val('Kerbol').prop('disabled', false)
      $('#bodyForm .modal-header h4').text("New origin body")
    
    $('#bodyName').val('').removeData('originalValue')
    $('#semiMajorAxis,#eccentricity,#inclination,#longitudeOfAscendingNode,#argumentOfPeriapsis,#meanAnomalyAtEpoch,#planetMass,#planetRadius,#timeOfPeriapsisPassage').val('')
    
    $('#bodyForm').modal()
    
  editBodyForm = (body, fixedReferenceBody = false) ->
    $('#bodyForm .form-group').removeClass('has-error')
    $('#bodyForm .help-block').hide()
    
    orbit = body.orbit
    if body.mass?
      $('#bodyType a[href="#planetFields"]').tab('show')
      $('#vesselFields input').val('')
      $('#meanAnomalyAtEpoch').val(orbit.meanAnomalyAtEpoch)
      $('#planetMass').val(body.mass)
      $('#planetRadius').val(body.radius / 1000)
    else
      $('#bodyType a[href="#vesselFields"]').tab('show')
      $('#planetFields input').val('')
      $('#timeOfPeriapsisPassage').val(shortKerbalDateString(orbit.timeOfPeriapsisPassage))
    
    $('#bodyForm .modal-header h4').text("Editing #{body.name()}")
    $('#bodyName').val(body.name()).data('originalValue', body.name())
    $('#referenceBodySelect').val(body.orbit.referenceBody.name()).prop('disabled', fixedReferenceBody)
    $('#semiMajorAxis').val(orbit.semiMajorAxis / 1000)
    $('#eccentricity').val(orbit.eccentricity)
    $('#inclination').val(orbit.inclination * 180 / Math.PI)
    $('#longitudeOfAscendingNode').val(orbit.longitudeOfAscendingNode * 180 / Math.PI)
    $('#argumentOfPeriapsis').val(orbit.argumentOfPeriapsis * 180 / Math.PI)
    
    $('#bodyForm').modal()
    
  $('#originAddBtn').click (event) -> addBodyForm()
  $('#originEditBtn').click (event) -> editBodyForm(CelestialBody[$('#originSelect').val()])
  
  $('#destinationAddBtn').click (event) ->
    referenceBody = CelestialBody[$('#originSelect').val()].orbit.referenceBody
    addBodyForm(referenceBody)
  
  $('#destinationEditBtn').click (event) ->
    body = CelestialBody[$('#destinationSelect').val()]
    editBodyForm(body, true)
    
  $('#bodyType a').click (event) ->
    event.preventDefault()
    $(this).tab('show')
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)
  
  $('#bodySaveBtn').click (event) ->
    # Check all values have been provided
    $('#bodyForm input:visible').filter(-> isBlank($(@).val()))
      .closest('.form-group').addClass('has-error')
      .find('.help-block').text('A value is required').show()
    
    # Abort if there are any outstanding errors
    if $('#bodyForm .form-group.has-error:visible').length > 0
      @disabled = true
      return
    
    # Collect the form values
    name = $('#bodyName').val()
    originalName = $('#bodyName').data('originalValue')
    
    referenceBody = CelestialBody[$('#referenceBodySelect').val()]
    semiMajorAxis = +$('#semiMajorAxis').val() * 1000
    eccentricity = +$('#eccentricity').val()
    inclination = +$('#inclination').val()
    longitudeOfAscendingNode = +$('#longitudeOfAscendingNode').val()
    argumentOfPeriapsis = +$('#argumentOfPeriapsis').val()
    if $('#planetFields').is(':visible')
      meanAnomalyAtEpoch = +$('#meanAnomalyAtEpoch').val()
      mass = +$('#planetMass').val()
      radius = +$('#planetRadius').val() * 1000
    else
      timeOfPeriapsisPassage = dateFromString($('#timeOfPeriapsisPassage').val())
    
    # Create the orbit and celestial body
    orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity, inclination,
      longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch, timeOfPeriapsisPassage)
    
    if originalName?
      originalBody = CelestialBody[originalName]
      delete CelestialBody[originalName]
    newBody = CelestialBody[name] = new CelestialBody(mass, radius, null, orbit)
    body.orbit.referenceBody = newBody for k, body of originalBody.children() if originalBody?
    
    # Update the origin and destination select boxes
    if $('#referenceBodySelect').prop('disabled')
      originalOrigin = $('#originSelect').val()
      prepareOrigins()
      $('#originSelect').val(originalOrigin).change()
      $('#destinationSelect').val(name).change()
    else
      originalDestination = $('#destinationSelect').val()
      prepareOrigins()
      $('#originSelect').val(name).change()
      if CelestialBody[originalDestination].orbit.referenceBody == referenceBody
        $('#destinationSelect').val(originalDestination).change()
    updateAdvancedControls()
    
    # Close the modal
    $('#bodyForm').modal('hide')

  # Body form input validation
  
  $('#bodyName').blur (event) ->
    $this = $(this)
    val = $this.val().trim()
    if isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('A name is required').show()
    else if val != $this.data('originalValue') and val of CelestialBody
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text("A body named #{val} already exists").show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)
    
  $('#semiMajorAxis,#planetMass,#planetRadius').blur (event) ->
    $this = $(this)
    val = $this.val()
    if isNaN(val) or isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val <= 0
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be greater than 0').show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  $('#eccentricity').blur (event) ->
    $this = $(this)
    val = $this.val()
    if isNaN(val) or isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val >= 1
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be between 0 and 1 (hyperbolic orbits are not supported)').show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  $('#inclination').blur (event) ->
    $this = $(this)
    val = $this.val()
    if isNaN(val) or isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val > 180
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text("Must be between 0\u00B0 and 180\u00B0").show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  $('#longitudeOfAscendingNode,#argumentOfPeriapsis').blur (event) ->
    $this = $(this)
    val = $this.val()
    if isNaN(val) or isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val > 360
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text("Must be between 0\u00B0 and 360\u00B0").show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  $('#meanAnomalyAtEpoch').blur (event) ->
    $this = $(this)
    val = $this.val()
    if isNaN(val) or isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val > 2 * Math.PI
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text("Must be between 0 and 2\u03c0 (6.28\u2026)").show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  $('#timeOfPeriapsisPassage').blur (event) ->
    $this = $(this)
    val = $this.val()
    if isBlank(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a Kerbal date').show()
    else if !/^\s*\d*[1-9]\d*\/\d*[1-9]\d*\s+\d+:\d+:\d+\s*$/.test(val)
      $this.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a valid Kerbal date: year/day hour:min:sec').show()
    else
      $this.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)
