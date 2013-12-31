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
    result += "0d" if t < 24 * 3600
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

angleString = (angle, precision = 0) ->
  (angle * 180 / Math.PI).toFixed(precision) + String.fromCharCode(0x00b0)

distanceFromScale = (distance, scale) ->
  distance * switch scale.trim()
    when "Gm" then 1e9
    when "Mm" then 1e6
    when "km" then 1e3
    else 1

dateFromString = (dateString) ->
  componentScales = [365, 24, 60, 60]
  components = dateString.split(':').reverse()
  time = 0
  scale = 1
  for c in components
    c = c - 1 if scale > 3600
    time += scale * c
    break if componentScales.length == 0
    scale *= componentScales.pop()
  time

$(document).ready ->
  $('#referenceBodySelect').change (event) ->
    referenceBody = CelestialBody[$(this).val()]
    
    s = $('#destinationSelect')
    previousDestination = s.val()
    s.empty()
    s.append($('<option>').text(k)) for k, v of CelestialBody when v?.orbit?.referenceBody == referenceBody
    s.val(previousDestination)
    s.val($('option:first', s).val()) unless s.val()?
    s.prop('disabled', s[0].childNodes.length == 0)
  
  $('#referenceBodySelect').change()
  $('#destinationSelect').val('Duna')
  
  $('#smaScaleMenu a').click (event) ->
    event.preventDefault()
    document.getElementById('smaScale').childNodes[0].nodeValue = $(this).text()
  
  $('#midcourseForm').submit (event) ->
    event.preventDefault()
    
    semiMajorAxis = distanceFromScale(+$('#sma').val(), $('#smaScale').text())
    eccentricity = +$('#eccentricity').val()
    inclination = +$('#inclination').val()
    longitudeOfAscendingNode = +$('#longitudeOfAscendingNode').val()
    argumentOfPeriapsis = +$('#argumentOfPeriapsis').val()
    meanAnomalyAtEpoch = +$('#meanAnomalyAtEpoch').val()
    
    referenceBody = CelestialBody[$('#referenceBodySelect').val()]
    destinationBody = CelestialBody[$('#destinationSelect').val()]
    eta = dateFromString($('#eta').val())
    burnTime = dateFromString($('#burnTime').val())
    
    # Form validation
    $('#midcourseForm .control-group').removeClass('error')
    errors = []
    errorFields = $('#midcourseForm input:text').filter(-> $(this).val().trim() == '')
    errors.push('all fields must be filled in') if errorFields.length > 0
    if semiMajorAxis < 0
      errorFields = errorFields.add('#sma')
      errors.push('hyperbolic transfer orbits are not supported')
    else if semiMajorAxis == 0 and $('#sma').val().trim() != ''
      errorFields = errorFields.add('#sma')
      errors.push('the semi-major axis cannot be 0')
    if eccentricity < 0 or eccentricity >= 1.0
      errorFields = errorFields.add('#eccentricity')
      errors.push('the eccentricity must be between 0 and 1')
    if inclination < 0 or inclination > 180
      errorFields = errorFields.add('#inclination')
      errors.push('the inclination must be between 0 and 180')
    if longitudeOfAscendingNode  < 0 or longitudeOfAscendingNode  > 360
      errorFields = errorFields.add('#longitudeOfAscendingNode ')
      errors.push('the longitude of the ascending node must be between 0 and 360')
    if argumentOfPeriapsis  < 0 or argumentOfPeriapsis  > 360
      errorFields = errorFields.add('#argumentOfPeriapsis ')
      errors.push('the argument of periapsis  must be between 0 and 360')
    if meanAnomalyAtEpoch  < 0 or meanAnomalyAtEpoch  > 2 * Math.PI
      errorFields = errorFields.add('#meanAnomalyAtEpoch')
      errors.push('the mean anomaly at epoch must be between 0 and 2&pi;')
    if burnTime < 0
      errorFields = errorFields.add('#burnTime')
      errors.push('the time of maneuver and estimated time of arrival must be greater than 0')
    if eta < (burnTime + 3600)
      errorFields = errorFields.add('#eta')
      errors.push('the estimated time of arrival must be at least one hour after the time of maneuver')
    if errorFields.length > 0
      errorFields.closest('.control-group').addClass('error')
      errors[0] = errors[0].charAt(0).toUpperCase() + errors[0].slice(1)
      errors = errors.slice(0,errors.length-2).concat([errors.slice(errors.length-2).join(' and ')])
      $('#validationMessage').html(errors.join(', ') + '.')
      $('#validationAlert:hidden').slideDown()
      return
    $('#validationAlert:visible').slideUp()
    
    orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch)
    
    burn = Orbit.courseCorrection(orbit, destinationBody.orbit, burnTime, eta)
    $('#burnDeltaV').text(burn.deltaV.toFixed(1) + " m/s")
    $('#burnPitch').text(angleString(burn.pitch, 2))
    $('#burnHeading').text(angleString(burn.heading, 2))
    $('#progradeDeltaV').text(burn.progradeDeltaV.toFixed(2) + " m/s")
    $('#normalDeltaV').text(burn.normalDeltaV.toFixed(2) + " m/s")
    $('#radialDeltaV').text(burn.radialDeltaV.toFixed(2) + " m/s")
    $('#arrivalTime').text(kerbalDateString(burn.arrivalTime))
    $('#burnDetails:hidden').slideDown()
