porkchopPlot = null
selectedTransfer = null

sign = (x) -> if x < 0 then -1 else 1

numberWithCommas = (n) ->
  n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')

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

showTransferDetailsForPoint = (point) ->
  mission = porkchopPlot.mission
  
  [x, y] = [point.x, point.y]
  t0 = mission.earliestDeparture + x * mission.xResolution
  dt = mission.shortestTimeOfFlight + y * mission.yResolution
  
  transfer = Orbit.transfer(mission.transferType, mission.originBody, mission.destinationBody, t0, dt, mission.initialOrbitalVelocity, mission.finalOrbitalVelocity)
  showTransferDetails(transfer, t0, dt)
  
showTransferDetails = (transfer, t0, dt) ->
  mission = porkchopPlot.mission
  t1 = t0 + dt
  transfer = Orbit.transferDetails(transfer, mission.originBody, t0, mission.initialOrbitalVelocity)
  selectedTransfer = transfer

  originOrbit = mission.originBody.orbit
  destinationOrbit = mission.destinationBody.orbit
  
  $('#departureTime').text(new KerbalTime(t0).toDateString()).attr(title: "UT: #{t0.toFixed()}s")
  $('#arrivalTime').text(new KerbalTime(t1).toDateString()).attr(title: "UT: #{t1.toFixed()}s")
  $('#timeOfFlight').text(new KerbalTime(dt).toDurationString()).attr(title: dt.toFixed() + "s")
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
    $('#planeChangeTime').text(new KerbalTime(transfer.planeChangeTime).toDateString())
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
  
$(document).ready ->
  celestialBodyForm = new CelestialBodyForm($('#bodyForm'))
  missionForm = new MissionForm($('#porkchopForm'), celestialBodyForm)
  porkchopPlot = new PorkchopPlot($('#porkchopContainer'))
  
  $(KerbalTime).on 'dateFormatChanged', (event) ->
    showTransferDetailsForPoint(porkchopPlot.selectedPoint) if porkchopPlot.selectedPoint?
  
  $(missionForm)
    .on 'submit', (event) ->
      $('#porkchopSubmit,#refineTransferBtn').prop('disabled', true)
      
      scrollTop = $('#porkchopCanvas').offset().top + $('#porkchopCanvas').height() - $(window).height()
      $("html,body").animate(scrollTop: scrollTop, 500) if $(document).scrollTop() < scrollTop
      
      porkchopPlot.calculate(missionForm.mission(), true)
      
  $(porkchopPlot)
    .on 'plotStarted', (event) ->
      $('#porkchopSubmit').prop('disabled', true)
    .on 'plotComplete', (event) ->
      showTransferDetailsForPoint(porkchopPlot.selectedPoint)
      $('#porkchopSubmit,#refineTransferBtn').prop('disabled', false)
    .on 'click', (event, point) ->
      showTransferDetailsForPoint(point)
  
  $('#ejectionDeltaVInfo').popover(html: true, content: ejectionDeltaVInfoContent)
    .click((event) -> event.preventDefault()).on 'show.bs.popover', ->
      $(this).next().find('.popover-content').html(ejectionDeltaVInfoContent())
  
  $('#refineTransferBtn').click (event) ->
    [x, y] = [porkchopPlot.selectedPoint.x, porkchopPlot.selectedPoint.y]
    mission = porkchopPlot.mission
    t0 = mission.earliestDeparture + x * mission.xResolution
    dt = mission.shortestTimeOfFlight + y * mission.yResolution
    
    transfer = Orbit.refineTransfer(selectedTransfer, mission.transferType, mission.originBody, mission.destinationBody, t0, dt, mission.initialOrbitalVelocity, mission.finalOrbitalVelocity)
    showTransferDetails(transfer, t0, dt)
