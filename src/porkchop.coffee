PLOT_WIDTH = 300
PLOT_HEIGHT = 300
PLOT_X_OFFSET = 70
TIC_LENGTH = 5

transferType = null
originBody = null
originOrbit = null
destinationOrbit = null
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

palette = []
palette.push([64, i, 255]) for i in [64...69]
palette.push([128, i, 255]) for i in [133..255]
palette.push([128, 255, i]) for i in [255..128]
palette.push([i, 255, 128]) for i in [128..255]
palette.push([255, i, 128]) for i in [255..128]

clamp = (n, min, max) -> Math.max(min, Math.min(n, max))

sign = (x) -> if x < 0 then -1 else 1

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

deltaVAbbr = (el, dv, prograde, normal) ->
  tooltip = numberWithCommas(prograde.toFixed(1)) + " m/s prograde; " +
    numberWithCommas(normal.toFixed(1)) + " m/s normal"
  el.attr(title: tooltip).text(numberWithCommas(dv.toFixed()) + " m/s")
  
angleString = (angle, precision = 0) ->
  (angle * 180 / Math.PI).toFixed(precision) + String.fromCharCode(0x00b0)

worker = new Worker("javascripts/porkchopworker.js")

worker.onmessage = (event) ->
  if 'progress' of event.data
    $('#porkchopProgress').show().find('.bar').width((event.data.progress * 100 | 0) + "%")
  else if 'deltaVs' of event.data
    $('#porkchopProgress').hide().find('.bar').width("0%")
    deltaVs = event.data.deltaVs
    deltaVs = new Float64Array(deltaVs) if deltaVs instanceof ArrayBuffer
    minDeltaV = event.data.minDeltaV
    maxDeltaV = 4 * minDeltaV
    selectedPoint = event.data.minDeltaVPoint
    
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
    drawPlot()
    showTransferDetails()
    
    $('#porkchopSubmit').prop('disabled', false)

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

showTransferDetails = ->
  if selectedPoint?
    [x, y] = [selectedPoint.x, selectedPoint.y]
    
    t0 = earliestDeparture + x * xScale / PLOT_WIDTH
    t1 = t0 + shortestTimeOfFlight + ((PLOT_HEIGHT-1) - y) * yScale / PLOT_HEIGHT
  
    trueAnomaly = originOrbit.trueAnomalyAt(t0)
    p0 = originOrbit.positionAtTrueAnomaly(trueAnomaly)
    v0 = originOrbit.velocityAtTrueAnomaly(trueAnomaly)
    n0 = originOrbit.normalVector()
  
    trueAnomaly = destinationOrbit.trueAnomalyAt(t1)
    p1 = destinationOrbit.positionAtTrueAnomaly(trueAnomaly)
    v1 = destinationOrbit.velocityAtTrueAnomaly(trueAnomaly)
  
    transfer = Orbit.transfer(transferType, originOrbit.referenceBody, t0, p0, v0, n0, t1, p1, v1, initialOrbitalVelocity, finalOrbitalVelocity, originBody)
  
    $('#departureTime').text(kerbalDateString(t0)).attr(title: "UT: #{t0.toFixed()}s")
    $('#arrivalTime').text(kerbalDateString(t1)).attr(title: "UT: #{t1.toFixed()}s")
    $('#timeOfFlight').text(durationString(t1 - t0)).attr(title: (t1 - t0).toFixed() + "s")
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
    deltaVAbbr($('#ejectionDeltaV'), transfer.ejectionDeltaV, transfer.ejectionProgradeDeltaV, transfer.ejectionNormalDeltaV)
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
      deltaVAbbr($('#insertionDeltaV'), transfer.insertionDeltaV, -transfer.insertionDeltaV, 0)
    else
      $('#insertionDeltaV').attr(title: null).text("N/A")
    $('#totalDeltaV').text(numberWithCommas(transfer.deltaV.toFixed()) + " m/s")
  
    $('#transferDetails:hidden').fadeIn()
  else
    $('#transferDetails:visible').fadeOut()

updateAdvancedControls = ->
  origin = CelestialBody[$('#originSelect').val()]
  destination = CelestialBody[$('#destinationSelect').val()]
  referenceBody = origin.orbit.referenceBody
  hohmannTransfer = Orbit.fromApoapsisAndPeriapsis(referenceBody, destination.orbit.semiMajorAxis, origin.orbit.semiMajorAxis, 0, 0, 0, 0)
  hohmannTransferTime = hohmannTransfer.period() / 2
  synodicPeriod = Math.abs(1 / (1 / destination.orbit.period() - 1 / origin.orbit.period()))
  
  minDeparture = ($('#earliestDepartureYear').val() - 1) * 365 + ($('#earliestDepartureDay').val() - 1)
  minDeparture *= 24 * 3600
  maxDeparture = minDeparture + Math.min(2 * synodicPeriod, 2 * origin.orbit.period())
  minDays = Math.max(hohmannTransferTime - destination.orbit.period(), hohmannTransferTime / 2) / 3600 / 24
  maxDays = minDays + Math.min(2 * destination.orbit.period(), hohmannTransferTime) / 3600 / 24
  minDays = if minDays < 10 then minDays.toFixed(2) else minDays.toFixed()
  maxDays = if maxDays < 10 then maxDays.toFixed(2) else maxDays.toFixed()
  
  $('#latestDepartureYear').val((maxDeparture / 3600 / 24 / 365 | 0) + 1)
  $('#latestDepartureDay').val((maxDeparture / 3600 / 24 % 365 | 0) + 1)
  $('#shortestTimeOfFlight').val(minDays)
  $('#longestTimeOfFlight').val(maxDays)

@prepareOrigins = -> #Globalized so bodies can be added in the console
  o = $('#originSelect')
  o.empty()
  (listBody = ( (body, elem) ->
    for k, v of CelestialBody when v?.orbit?.referenceBody == body
      group = $('<optgroup>')
      listBody(v, group)
      if group.children().size() > 0
        group.prepend($('<option>').text(k))
        group.attr('label', k + ' System')
        elem.append(group)
      else
        elem.append($('<option>').text(k))
  ))(CelestialBody.Kerbol, o)

$(document).ready ->
  canvasContext = $('#porkchopCanvas')[0].getContext('2d')
  plotImageData = canvasContext.createImageData(PLOT_WIDTH, PLOT_HEIGHT)
  
  prepareCanvas()
  prepareOrigins()
  
  $('#porkchopCanvas').mousemove (event) ->
    if deltaVs?
      offsetX = event.offsetX ? (event.pageX - $('#porkchopCanvas').offset().left) | 0
      offsetY = event.offsetY ? (event.pageY - $('#porkchopCanvas').offset().top) | 0
      x = offsetX - PLOT_X_OFFSET
      y = offsetY
      pointer = { x: x, y: y } if x >= 0 and x < PLOT_WIDTH and y < PLOT_HEIGHT
      drawPlot(pointer)
      
  $('#porkchopCanvas').mouseleave (event) -> drawPlot()
  
  $('#porkchopCanvas').click (event) ->
    if deltaVs?
      offsetX = event.offsetX ? (event.pageX - $('#porkchopCanvas').offset().left) | 0
      offsetY = event.offsetY ? (event.pageY - $('#porkchopCanvas').offset().top) | 0
      x = offsetX - PLOT_X_OFFSET
      y = offsetY
      if x >= 0 and x < PLOT_WIDTH and y < PLOT_HEIGHT and !isNaN(deltaVs[(y * PLOT_WIDTH + x) | 0])
        selectedPoint = { x: x, y: y }
        drawPlot(selectedPoint)
        showTransferDetails()
        ga('send', 'event', 'porkchop', 'click', "#{x},#{y}")
        
  $('#originSelect').change (event) ->
    origin = CelestialBody[$(this).val()]
    referenceBody = origin.orbit.referenceBody
    
    s = $('#destinationSelect')
    previousDestination = s.val()
    s.empty()
    s.append($('<option>').text(k)) for k, v of CelestialBody when v != origin and v?.orbit?.referenceBody == referenceBody
    s.val(previousDestination)
    s.val($('option:first', s).val()) unless s.val()?
    s.prop('disabled', s[0].childNodes.length == 0)
    
    updateAdvancedControls()
  
  $('#destinationSelect').change (event) ->
    updateAdvancedControls()
    
  $('#originSelect').change()
  $('#destinationSelect').val('Duna')
  $('#destinationSelect').change()
  
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
    $('#porkchopSubmit').prop('disabled', true)
    
    scrollTop = $('#porkchopCanvas').offset().top + $('#porkchopCanvas').height() - $(window).height()
    $("html,body").animate(scrollTop: scrollTop, 500) if $(document).scrollTop() < scrollTop
    
    originBodyName = $('#originSelect').val()
    destinationBodyName = $('#destinationSelect').val()
    initialOrbit = $('#initialOrbit').val().trim()
    finalOrbit = $('#finalOrbit').val().trim()
    transferType = $('#transferTypeSelect').val()
    
    originBody = CelestialBody[originBodyName]
    destinationBody = CelestialBody[destinationBodyName]
    
    if +initialOrbit == 0
      initialOrbitalVelocity = 0
    else
      initialOrbitalVelocity = originBody.circularOrbitVelocity(initialOrbit * 1e3)
        
    if finalOrbit
      if +finalOrbit == 0
        finalOrbitalVelocity = 0
      else
        finalOrbitalVelocity = destinationBody.circularOrbitVelocity(finalOrbit * 1e3)
    else
      finalOrbitalVelocity = null
    
    earliestDeparture = ($('#earliestDepartureYear').val() - 1) * 365 + ($('#earliestDepartureDay').val() - 1)
    earliestDeparture *= 24 * 3600
    
    latestDeparture = ($('#latestDepartureYear').val() - 1) * 365 + ($('#latestDepartureDay').val() - 1)
    latestDeparture *= 24 * 3600
    xScale = latestDeparture - earliestDeparture
    
    shortestTimeOfFlight = +$('#shortestTimeOfFlight').val() * 24 * 3600
    yScale = +$('#longestTimeOfFlight').val() * 24 * 3600 - shortestTimeOfFlight
    
    originOrbit = originBody.orbit
    destinationOrbit = destinationBody.orbit
    
    ctx = canvasContext
    ctx.clearRect(PLOT_X_OFFSET, 0, PLOT_WIDTH, PLOT_HEIGHT)
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
      transferType: transferType, originOrbit: originOrbit, destinationOrbit: destinationOrbit,
      initialOrbitalVelocity: initialOrbitalVelocity, finalOrbitalVelocity: finalOrbitalVelocity,
      earliestDeparture: earliestDeparture, xScale: xScale,
      shortestTimeOfFlight: shortestTimeOfFlight, yScale: yScale)

    description = "#{originBodyName} @#{+initialOrbit}km to #{destinationBodyName}"
    description += " @#{+finalOrbit}km" if finalOrbit
    description += " after day #{earliestDeparture / (24 * 3600)} via #{$('#transferTypeSelect option:selected').text()} transfer"
    ga('send', 'event', 'porkchop', 'submit', description)
