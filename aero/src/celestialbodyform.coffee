isBlank = (str) -> !/\S/.test(str)

class CelestialBodyForm
  constructor: (@form) ->
    $('#bodyType a', @form).click (event) =>
      event.preventDefault()
      $(event.target).tab('show')
      $('#bodySaveBtn', @form).prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)
      
    $('#bodySaveBtn', @form).click (event) => @save()
    
    # Input validation
    $('#bodyName', @form).blur (event) => @validateName(event.target)
    $('#semiMajorAxis,#planetMass,#planetRadius').blur (event) => @validateGreaterThanZero(event.target)
    $('#eccentricity', @form).blur (event) => @validateEccentricity(event.target)
    $('#inclination', @form).blur (event) => @validateAngle(event.target, 180)
    $('#longitudeOfAscendingNode,#argumentOfPeriapsis', @form).blur (event) => @validateAngle(event.target)
    $('#meanAnomalyAtEpoch', @form).blur (event) => @validateMeanAnomaly(event.target)
    $('#timeOfPeriapsisPassage', @form).blur (event) => @validateDate(event.target)
    
  add: (referenceBody = null) ->
    $('.form-group', @form).removeClass('has-error')
    $('.help-block', @form).hide()
    
    $('#bodyType a[href="#planetFields"]', @form).tab('show')
    
    if referenceBody?
      $('#referenceBodySelect', @form).val(referenceBody.name()).prop('disabled', true)
      $('.modal-header h4', @form).text("New destination orbiting #{referenceBody.name()}")
    else
      $('#referenceBodySelect', @form).val('Kerbol').prop('disabled', false)
      $('.modal-header h4', @form).text("New origin body")
    
    $('#bodyName', @form).val('').removeData('originalValue')
    $('#semiMajorAxis,#eccentricity,#inclination,#longitudeOfAscendingNode,#argumentOfPeriapsis,#meanAnomalyAtEpoch,#planetMass,#planetRadius,#timeOfPeriapsisPassage', @form).val('')
    
    @form.modal()
  
  edit: (body, fixedReferenceBody = false) ->
    $('.form-group', @form).removeClass('has-error')
    $('.help-block', @form).hide()
    
    orbit = body.orbit
    if body.mass?
      $('#bodyType a[href="#planetFields"]', @form).tab('show')
      $('#vesselFields input', @form).val('')
      $('#meanAnomalyAtEpoch', @form).val(orbit.meanAnomalyAtEpoch)
      $('#planetMass', @form).val(body.mass)
      $('#planetRadius', @form).val(body.radius / 1000)
    else
      $('#bodyType a[href="#vesselFields"]', @form).tab('show')
      $('#planetFields input', @form).val('')
      $('#timeOfPeriapsisPassage', @form).val(new KerbalTime(orbit.timeOfPeriapsisPassage).toShortDateString())
    
    $('.modal-header h4', @form).text("Editing #{body.name()}")
    $('#bodyName', @form).val(body.name()).data('originalValue', body.name())
    $('#referenceBodySelect', @form).val(body.orbit.referenceBody.name()).prop('disabled', fixedReferenceBody)
    $('#semiMajorAxis', @form).val(orbit.semiMajorAxis / 1000)
    $('#eccentricity', @form).val(orbit.eccentricity)
    $('#inclination', @form).val(orbit.inclination * 180 / Math.PI)
    $('#longitudeOfAscendingNode', @form).val(orbit.longitudeOfAscendingNode * 180 / Math.PI)
    $('#argumentOfPeriapsis', @form).val(orbit.argumentOfPeriapsis * 180 / Math.PI)
    
    @form.modal()
  
  save: ->
    # Check all values have been provided
    $('input:visible', @form).filter(-> isBlank($(@).val()))
      .closest('.form-group').addClass('has-error')
      .find('.help-block').text('A value is required').show()
    
    # Abort if there are any outstanding errors
    if $('.form-group.has-error:visible', @form).length > 0
      $('#bodySaveBtn', @form).disabled = true
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
      timeOfPeriapsisPassage = KerbalTime.parse($('#timeOfPeriapsisPassage').val())
    
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
    @form.modal('hide')

  # Input validations
  validateName: (input) ->
    $input = $(input)
    val = $input.val().trim()
    if isBlank(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('A name is required').show()
    else if val != $input.data('originalValue') and val of CelestialBody
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text("A body named #{val} already exists").show()
    else
      $input.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)
    
  validateGreaterThanZero: (input) ->
    $input = $(input)
    val = $input.val()
    if isNaN(val) or isBlank(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val <= 0
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be greater than 0').show()
    else
      $input.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  validateEccentricity: (input) ->
    $input = $(input)
    val = $input.val()
    if isNaN(val) or isBlank(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val >= 1
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be between 0 and 1 (hyperbolic orbits are not supported)').show()
    else
      $input.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  validateAngle: (input, maxAngle = 360) ->
    $input = $(input)
    val = $input.val()
    if isNaN(val) or isBlank(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val > maxAngle
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text("Must be between 0\u00B0 and #{maxAngle}\u00B0").show()
    else
      $input.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  validateMeanAnomaly: (input) ->
    $input = $(input)
    val = $input.val()
    if isNaN(val) or isBlank(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a number').show()
    else if val < 0 or val > 2 * Math.PI
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text("Must be between 0 and 2\u03c0 (6.28\u2026)").show()
    else
      $input.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

  validateDate: (input) ->
    $input = $(this)
    val = $input.val()
    if isBlank(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a Kerbal date').show()
    else if !/^\s*\d*[1-9]\d*\/\d*[1-9]\d*\s+\d+:\d+:\d+\s*$/.test(val)
      $input.closest('.form-group').addClass('has-error')
        .find('.help-block').text('Must be a valid Kerbal date: year/day hour:min:sec').show()
    else
      $input.closest('.form-group').removeClass('has-error')
        .find('.help-block').hide()
    $('#bodySaveBtn').prop('disabled', $('#bodyForm .form-group.has-error:visible').length > 0)

(exports ? this).CelestialBodyForm = CelestialBodyForm
