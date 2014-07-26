porkchopPlot = null
selectedTransfer = null

# Default to Kerbin time
hoursPerDay = 6
daysPerYear = 426

sign = (x) -> if x < 0 then -1 else 1

numberWithCommas = (n) ->
  n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')

secondsPerDay = -> hoursPerDay * 3600

hms = (t) ->
  hours = (t / 3600) | 0
  t %= 3600
  mins = (t / 60) | 0
  secs = t % 60
  [hours, mins, secs]

ydhms = (t) ->
  [hours, mins, secs] = hms(+t)
  days = (hours / hoursPerDay) | 0
  hours = hours % hoursPerDay
  years = (days / daysPerYear) | 0
  days = days % daysPerYear
  [years, days, hours, mins, secs]

kerbalDate = (t) ->
  [years, days, hours, mins, secs] = ydhms(+t)
  [years + 1, days + 1, hours, mins, secs]

durationSeconds = (years = 0, days = 0, hours = 0, mins = 0, secs = 0) ->
  ((((+years * daysPerYear) + +days) * hoursPerDay + +hours) * 60 + +mins) * 60 + +secs

dateSeconds = (year = 0, day = 0, hour = 0, min = 0, sec = 0) ->
  durationSeconds(+year - 1, +day - 1, +hour, +min, +sec)

hmsString = (hour, min, sec) ->
  min = "0#{min}" if min < 10
  sec = "0#{sec}" if sec < 10
  "#{hour}:#{min}:#{sec}"
  
kerbalDateString = (t) ->
  [year, day, hour, min, sec] = kerbalDate(+t.toFixed())
  "Year #{year}, day #{day} at #{hmsString(hour, min, sec)}"

shortKerbalDateString = (t) ->
  [year, day, hour, min, sec] = kerbalDate(+t.toFixed())
  "#{year}/#{day} #{hmsString(hour, min, sec)}"

dateFromString = (dateString) ->
  components = dateString.match(/(\d+)\/(\d+)\s+(\d+):(\d+):(\d+)/)
  components.shift()
  dateSeconds(components...)

durationString = (t) ->
  [years, days, hours, mins, secs] = ydhms(t.toFixed())
  result = ""
  result += years + " years " if years > 0
  result += days + " days " if years > 0 or days > 0
  result + hmsString(hours, mins, secs)

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
  
  departureRange = Math.min(2 * synodicPeriod, 2 * origin.orbit.period()) / secondsPerDay()
  if departureRange < 0.1
    departureRange = +departureRange.toFixed(2)
  else if departureRange < 1
    departureRange = +departureRange.toFixed(1)
  else
    departureRange = +departureRange.toFixed()
  minDeparture = dateSeconds($('#earliestDepartureYear').val(), $('#earliestDepartureDay').val()) / secondsPerDay()
  maxDeparture = minDeparture + departureRange
  
  minDays = Math.max(hohmannTransferTime - destination.orbit.period(), hohmannTransferTime / 2) / secondsPerDay()
  maxDays = minDays + Math.min(2 * destination.orbit.period(), hohmannTransferTime) / secondsPerDay()
  minDays = if minDays < 10 then minDays.toFixed(2) else minDays.toFixed()
  maxDays = if maxDays < 10 then maxDays.toFixed(2) else maxDays.toFixed()
  
  $('#latestDepartureYear').val((maxDeparture / daysPerYear | 0) + 1)
  $('#latestDepartureDay').val((maxDeparture % daysPerYear) + 1)
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
  porkchopPlot = new PorkchopPlot($('#porkchopContainer'), secondsPerDay())
  $(porkchopPlot)
    .on 'plotComplete', (event) ->
      showTransferDetailsForPoint(porkchopPlot.selectedPoint)
      $('#porkchopSubmit,#porkchopContainer button,#refineTransferBtn').prop('disabled', false)
    .on 'click', (event, point) ->
      showTransferDetailsForPoint(point)
      ga('send', 'event', 'porkchop', 'click', "#{point.x},#{point.y}")
  
  prepareOrigins()
  
  $('#refineTransferBtn').click (event) ->
    [x, y] = [porkchopPlot.selectedPoint.x, porkchopPlot.selectedPoint.y]
    mission = porkchopPlot.mission
    t0 = mission.earliestDeparture + x * mission.xResolution
    dt = mission.shortestTimeOfFlight + y * mission.yResolution
    
    transfer = Orbit.refineTransfer(selectedTransfer, mission.transferType, mission.originBody, mission.destinationBody, t0, dt, mission.initialOrbitalVelocity, mission.finalOrbitalVelocity)
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
  
  $('#earthTime').click ->
    hoursPerDay = 24
    daysPerYear = 365
    porkchopPlot.secondsPerDay = secondsPerDay()
    updateAdvancedControls()
  
  $('#kerbinTime').click ->
    hoursPerDay = 6
    daysPerYear = 426
    porkchopPlot.secondsPerDay = secondsPerDay()
    updateAdvancedControls()
    
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
  $('#earthTime').click() if $('#earthTime').prop('checked')
  
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
    
    earliestDeparture = dateSeconds(+$('#earliestDepartureYear').val(), +$('#earliestDepartureDay').val())
    latestDeparture = dateSeconds(+$('#latestDepartureYear').val(), +$('#latestDepartureDay').val())
    xScale = latestDeparture - earliestDeparture
    
    shortestTimeOfFlight = durationSeconds(0, +$('#shortestTimeOfFlight').val())
    yScale = durationSeconds(0, +$('#longestTimeOfFlight').val()) - shortestTimeOfFlight
    
    mission = {
      transferType: transferType
      originBody: originBody
      destinationBody: destinationBody
      initialOrbitalVelocity: initialOrbitalVelocity
      finalOrbitalVelocity: finalOrbitalVelocity
      earliestDeparture: earliestDeparture
      shortestTimeOfFlight: shortestTimeOfFlight
      xScale: xScale
      yScale: yScale
    }
    
    porkchopPlot.calculate(mission, true)

    description = "#{originBodyName} @#{+initialOrbit}km to #{destinationBodyName}"
    description += " @#{+finalOrbit}km" if finalOrbit
    description += " after day #{earliestDeparture / secondsPerDay()} via #{$('#transferTypeSelect option:selected').text()} transfer"
    ga('send', 'event', 'porkchop', 'submit', description)

  celestialBodyForm = new CelestialBodyForm($('#bodyForm'))
  
  $('#originAddBtn').click (event) -> celestialBodyForm.add()
  $('#originEditBtn').click (event) -> celestialBodyForm.edit(CelestialBody[$('#originSelect').val()])
  
  $('#destinationAddBtn').click (event) ->
    referenceBody = CelestialBody[$('#originSelect').val()].orbit.referenceBody
    celestialBodyForm.add(referenceBody)
  
  $('#destinationEditBtn').click (event) ->
    body = CelestialBody[$('#destinationSelect').val()]
    celestialBodyForm.edit(body, true)