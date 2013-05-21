importScripts('numeric-1.2.6.min.js')
importScripts('quaternion.js')
importScripts('orbit.js')

WIDTH = 300
HEIGHT = 300

@onmessage = (event) ->
  departureOrbit = Orbit.fromJSON(event.data.departureOrbit)
  destinationOrbit = Orbit.fromJSON(event.data.destinationOrbit)
  earliestDeparture = event.data.earliestDeparture
  earliestArrival = event.data.earliestArrival
  xResolution = event.data.xScale / WIDTH
  yResolution = event.data.yScale / HEIGHT
  referenceBody = departureOrbit.referenceBody
  
  # Pre-calculate destination positions and velocities
  departurePositions = []
  departureVelocities = []
  for x in [0...WIDTH]
    departureTime = earliestDeparture + x * xResolution
    nu = departureOrbit.trueAnomalyAt(departureTime)
    departurePositions[x] = departureOrbit.positionAtTrueAnomaly(nu)
    departureVelocities[x] = departureOrbit.velocityAtTrueAnomaly(nu)
  
  deltaVs = new Float64Array(WIDTH * HEIGHT)
  i = 0
  minDeltaV = Infinity
  maxDeltaV = 0
  lastProgress = 0
  for y in [0...HEIGHT]
    arrivalTime = earliestArrival + ((HEIGHT-1) - y) * yResolution
    nu = destinationOrbit.trueAnomalyAt(arrivalTime)
    p2 = destinationOrbit.positionAtTrueAnomaly(nu)
    v2 = destinationOrbit.velocityAtTrueAnomaly(nu)
    
    for x in [0...WIDTH]
      departureTime = earliestDeparture + x * xResolution
      if arrivalTime <= departureTime
        deltaVs[i++] = NaN
        continue
      p1 = departurePositions[x]
      v1 = departureVelocities[x]
      dt = arrivalTime - departureTime
  
      # TODO: Use heuristic so we don't have to calculate both transfer directions
      # (e.g. if angle is < 170 or > 190 then only go clockwise)
      shortWayTransferVelocities = Orbit.transferVelocities(referenceBody, p1, p2, dt, false)
      longWayTransferVelocities = Orbit.transferVelocities(referenceBody, p1, p2, dt, true)
  
      shortDeltaV = numeric.norm2(numeric.subVV(v1, shortWayTransferVelocities[0])) +
        numeric.norm2(numeric.subVV(v2, shortWayTransferVelocities[1]))
      longDeltaV = numeric.norm2(numeric.subVV(v1, longWayTransferVelocities[0])) +
        numeric.norm2(numeric.subVV(v2, longWayTransferVelocities[1]))
      deltaVs[i++] = deltaV = Math.min(shortDeltaV, longDeltaV)

      minDeltaV = Math.min(deltaV, minDeltaV)
      maxDeltaV = Math.max(deltaV, maxDeltaV)
    
    now = Date.now()
    if now - lastProgress > 100
      postMessage(progress: (y + 1) / HEIGHT)
      lastProgress = now
  
  try
    postMessage({ deltaVs: deltaVs.buffer, minDeltaV: minDeltaV, maxDeltaV: maxDeltaV }, [deltaVs.buffer])
  catch error
    if error instanceof TypeError
      postMessage({ deltaVs: deltaVs.buffer, minDeltaV: minDeltaV, maxDeltaV: maxDeltaV })
    else
      throw error
