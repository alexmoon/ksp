(exports ? this).prepareOrigins = prepareOrigins = ->
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

class MissionForm
  constructor: (@form, @celestialBodyForm) ->
    prepareOrigins()
    
    $('.altitude').tooltip(container: 'body')
    
    $('#earthTime').click (=> KerbalTime.setDateFormat(24, 365); updateAdvancedControls.call(@))
    $('#kerbinTime').click (=> KerbalTime.setDateFormat(6, 426); updateAdvancedControls.call(@))
    $('#earthTime').click() if $('#earthTime').prop('checked')
    
    $('#originSelect').change (event) => @setOrigin($(event.target).val())
    $('#destinationSelect').change (event) => @setDestination($(event.target).val())
    @setOrigin('Kerbin')
    @setDestination('Duna')
    
    $('#originAddBtn').click (event) => @celestialBodyForm.add()
    $('#originEditBtn').click (event) => @celestialBodyForm.edit(@origin())
  
    $('#destinationAddBtn').click (event) =>
      referenceBody = @origin().orbit.referenceBody
      @celestialBodyForm.add(referenceBody)
  
    $('#destinationEditBtn').click (event) => @celestialBodyForm.edit(@destination(), true)
      
    $('#noInsertionBurnCheckbox').change (event) =>
      $('#finalOrbit').attr("disabled", $(event.target).is(":checked")) if @destination().mass?
  
    $('#showAdvancedControls').click (event) => @showAdvancedControls(!@advancedControlsVisible())
  
    $('#earliestDepartureYear,#earliestDepartureDay').change (event) => @adjustLatestDeparture()
    $('#shortestTimeOfFlight,#longestTimeOfFlight').change (event) ->
      setTimeOfFlight(+$('#shortestTimeOfFlight').val(), +$('#longestTimeOfFlight').val(), event.target.id == 'shortestTimeOfFlight')
    
    @form.bind 'reset', (event) => setTimeout((=> setOrigin('Kerbin'); setDestination('Duna')), 0)
    @form.submit ((event) => event.preventDefault(); $(@).trigger('submit'))
  
  origin: ->
    CelestialBody[$('#originSelect').val()]
  
  destination: ->
    CelestialBody[$('#destinationSelect').val()]
  
  setOrigin: (newOriginName) ->
    $('#originSelect').val(newOriginName)
    origin = CelestialBody[newOriginName]
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
    
    updateAdvancedControls.call(@)
  
  setDestination: (newDestinationName) ->
    $('#destinationSelect').val(newDestinationName)
    $('#finalOrbit').attr("disabled", !CelestialBody[newDestinationName].mass?)
    updateAdvancedControls.call(@)
  
  advancedControlsVisible: ->
    $('#showAdvancedControls').text().indexOf('Hide') != -1
  
  showAdvancedControls: (show) ->
    if show
      $('#showAdvancedControls').text('Hide advanced settings...')
      $('#advancedControls').slideDown()
    else
      $('#showAdvancedControls').text('Show advanced settings...')
      $('#advancedControls').slideUp()
  
  adjustLatestDeparture: ->
    if !@advancedControlsVisible()
      updateAdvancedControls.call(@)
    else
      if +$('#earliestDepartureYear').val() > +$('#latestDepartureYear').val()
        $('#latestDepartureYear').val($('#earliestDepartureYear').val())
    
      if +$('#earliestDepartureYear').val() == +$('#latestDepartureYear').val()
        if +$('#earliestDepartureDay').val() >= +$('#latestDepartureDay').val()
          $('#latestDepartureDay').val(+$('#earliestDepartureDay').val() + 1)
  
  setTimeOfFlight: (shortest, longest, preserveShortest = true) ->
    shortest = 1 if shortest <= 0
    longest = 2 if longest <= 0
    
    if shortest >= longest
      if preserveShortest
        longest = shortest + 1
      else if longest > 1
        shortest = longest - 1
      else
        shortest = longest / 2
    
    $('#shortestTimeOfFlight').val(shortest)
    $('#longestTimeOfFlight').val(longest)
  
  mission: ->
    origin = @origin()
    destination = @destination()
    initialOrbit = $('#initialOrbit').val().trim()
    finalOrbit = $('#finalOrbit').val().trim()
    transferType = $('#transferTypeSelect').val()
    
    if !origin.mass? or +initialOrbit == 0
      initialOrbitalVelocity = 0
    else
      initialOrbitalVelocity = origin.circularOrbitVelocity(initialOrbit * 1e3)
        
    if $('#noInsertionBurnCheckbox').is(":checked")
      finalOrbitalVelocity = null
    else if !destination.mass? or +finalOrbit == 0
      finalOrbitalVelocity = 0
    else
      finalOrbitalVelocity = destination.circularOrbitVelocity(finalOrbit * 1e3)
    
    earliestDeparture = KerbalTime.fromDate(+$('#earliestDepartureYear').val(), +$('#earliestDepartureDay').val()).t
    latestDeparture = KerbalTime.fromDate(+$('#latestDepartureYear').val(), +$('#latestDepartureDay').val()).t
    xScale = latestDeparture - earliestDeparture
    
    shortestTimeOfFlight = KerbalTime.fromDuration(0, +$('#shortestTimeOfFlight').val()).t
    yScale = KerbalTime.fromDuration(0, +$('#longestTimeOfFlight').val()).t - shortestTimeOfFlight
    
    mission = {
      transferType: transferType
      originBody: origin
      destinationBody: destination
      initialOrbitalVelocity: initialOrbitalVelocity
      finalOrbitalVelocity: finalOrbitalVelocity
      earliestDeparture: earliestDeparture
      shortestTimeOfFlight: shortestTimeOfFlight
      xScale: xScale
      yScale: yScale
    }  

  # Private methods
  updateAdvancedControls = ->
    origin = @origin()
    destination = @destination()
    referenceBody = origin.orbit.referenceBody
    hohmannTransfer = Orbit.fromApoapsisAndPeriapsis(referenceBody, destination.orbit.semiMajorAxis, origin.orbit.semiMajorAxis, 0, 0, 0, 0)
    hohmannTransferTime = hohmannTransfer.period() / 2
    synodicPeriod = Math.abs(1 / (1 / destination.orbit.period() - 1 / origin.orbit.period()))
  
    departureRange = Math.min(2 * synodicPeriod, 2 * origin.orbit.period()) / KerbalTime.secondsPerDay()
    if departureRange < 0.1
      departureRange = +departureRange.toFixed(2)
    else if departureRange < 1
      departureRange = +departureRange.toFixed(1)
    else
      departureRange = +departureRange.toFixed()
    minDeparture = KerbalTime.fromDate($('#earliestDepartureYear').val(), $('#earliestDepartureDay').val()).t / KerbalTime.secondsPerDay()
    maxDeparture = minDeparture + departureRange
  
    minDays = Math.max(hohmannTransferTime - destination.orbit.period(), hohmannTransferTime / 2) / KerbalTime.secondsPerDay()
    maxDays = minDays + Math.min(2 * destination.orbit.period(), hohmannTransferTime) / KerbalTime.secondsPerDay()
    minDays = if minDays < 10 then minDays.toFixed(2) else minDays.toFixed()
    maxDays = if maxDays < 10 then maxDays.toFixed(2) else maxDays.toFixed()
  
    $('#latestDepartureYear').val((maxDeparture / KerbalTime.daysPerYear | 0) + 1)
    $('#latestDepartureDay').val((maxDeparture % KerbalTime.daysPerYear) + 1)
    $('#shortestTimeOfFlight').val(minDays)
    $('#longestTimeOfFlight').val(maxDays)
  
    $('#finalOrbit').attr("disabled", $('#noInsertionBurnCheckbox').is(":checked")) if destination.mass?


(exports ? this).MissionForm = MissionForm
