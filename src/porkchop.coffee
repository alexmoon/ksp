WIDTH = 720
HEIGHT = 720

clamp = (n, min, max) -> Math.max(min, Math.min(n, max))

palette = []
palette.push([0, i, 255]) for i in [0..255]
palette.push([0, 255, i]) for i in [255..0]
palette.push([i, 255, 0]) for i in [0..255]
palette.push([255, i, 0]) for i in [255..0]

worker = new Worker("javascripts/porkchopworker.js")

worker.onmessage = (event) ->
  if 'progress' of event.data
    $('#porkchopProgress .bar').show().width((event.data.progress * 100 | 0) + "%")
  else if 'deltaVs' of event.data
    $('#porkchopProgress .bar').hide().width("0%")
    deltaVs = new Float64Array(event.data.deltaVs)
    minDeltaV = event.data.minDeltaV
    maxDeltaV = 4 * minDeltaV
    
    $('#porkchopCanvas').draw
      fn: (ctx) ->
        imageData = ctx.createImageData(WIDTH, HEIGHT)
        i = 0
        j = 0
        for y in [0...HEIGHT]
          for x in [0...WIDTH]
            deltaV = deltaVs[i++]
            relativeDeltaV = (clamp(deltaV, minDeltaV, maxDeltaV) - minDeltaV) / (maxDeltaV - minDeltaV)
            colorIndex = Math.min(relativeDeltaV * palette.length | 0, palette.length - 1)
            color = palette[colorIndex]
            imageData.data[j++] = color[0]
            imageData.data[j++] = color[1]
            imageData.data[j++] = color[2]
            imageData.data[j++] = 128
            
        ctx.putImageData(imageData, 0, 0)

$(document).ready ->
  $('#porkchopForm').submit (event) ->
    event.preventDefault()
    
    departureOrbit = CelestialBody[$('#origin').val()].orbit
    destinationOrbit = CelestialBody[$('#destination').val()].orbit
    
    earliestDeparture = ($('#earliestDepartureYear').val() - 1) * 365 + ($('#earliestDepartureDay').val() - 1)
    earliestDeparture *= 24 * 3600
    earliestArrival = ($('#earliestArrivalYear').val() - 1) * 365 + ($('#earliestArrivalDay').val() - 1)
    earliestArrival *= 24 * 3600
    
    if earliestArrival <= earliestDeparture
      hohmannTransfer = Orbit.fromApoapsisAndPeriapsis(departureOrbit.referenceBody, destinationOrbit.semiMajorAxis, departureOrbit.semiMajorAxis, 0, 0, 0, 0)
      earliestArrival = earliestDeparture + hohmannTransfer.period() / 4
      $('#earliestArrivalYear').val(Math.floor(earliestArrival / 3600 / 24 / 365) + 1)
      $('#earliestArrivalDay').val(Math.floor(earliestArrival / 3600 / 24) % 365 + 1)
    
    xScale = 2 * Math.min(departureOrbit.period(), destinationOrbit.period())
    yScale = xScale
    
    $('#porkchopCanvas').clearCanvas()
    
    worker.postMessage(
      departureOrbit: departureOrbit, destinationOrbit: destinationOrbit,
      earliestDeparture: earliestDeparture, xScale: xScale,
      earliestArrival: earliestArrival, yScale: yScale)
