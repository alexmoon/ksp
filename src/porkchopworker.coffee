importScripts('numeric-1.2.6.min.js')
importScripts('quaternion.js')
importScripts('orbit.js')

WIDTH = 300
HEIGHT = 300

injectionDeltaV = (initialVelocity, hyperbolicExcessVelocity) ->
  vinf = hyperbolicExcessVelocity
  v0 = Math.sqrt(vinf * vinf + 2 * initialVelocity * initialVelocity) # Eq. 5.35
  v0 - initialVelocity # Eq. 5.36
  
@onmessage = (event) ->
  originOrbit = Orbit.fromJSON(event.data.originOrbit)
  initialOrbitalVelocity = event.data.initialOrbitalVelocity
  destinationOrbit = Orbit.fromJSON(event.data.destinationOrbit)
  finalOrbitalVelocity = event.data.finalOrbitalVelocity
  earliestDeparture = event.data.earliestDeparture
  earliestArrival = event.data.earliestArrival
  xResolution = event.data.xScale / WIDTH
  yResolution = event.data.yScale / HEIGHT
  referenceBody = originOrbit.referenceBody
  
  # Pre-calculate destination positions and velocities
  originPositions = []
  originVelocities = []
  for x in [0...WIDTH]
    departureTime = earliestDeparture + x * xResolution
    nu = originOrbit.trueAnomalyAt(departureTime)
    originPositions[x] = originOrbit.positionAtTrueAnomaly(nu)
    originVelocities[x] = originOrbit.velocityAtTrueAnomaly(nu)
  
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
      p1 = originPositions[x]
      v1 = originVelocities[x]
      dt = arrivalTime - departureTime
  
      # TODO: Use heuristic so we don't have to calculate both transfer directions
      # (e.g. if angle is < 170 or > 190 then only go clockwise)
      shortWayTransferVelocities = Orbit.transferVelocities(referenceBody, p1, p2, dt, false)
      longWayTransferVelocities = Orbit.transferVelocities(referenceBody, p1, p2, dt, true)
      
      shortEjectionDeltaV = numeric.norm2(numeric.subVV(shortWayTransferVelocities[0], v1))
      longEjectionDeltaV = numeric.norm2(numeric.subVV(longWayTransferVelocities[0], v1))
      if initialOrbitalVelocity?
        shortEjectionDeltaV = injectionDeltaV(initialOrbitalVelocity, shortEjectionDeltaV)
        longEjectionDeltaV = injectionDeltaV(initialOrbitalVelocity, longEjectionDeltaV)
      
      if finalOrbitalVelocity == 0
        shortInsertionDeltaV = 0
        longInsertionDeltaV = 0
      else
        shortInsertionDeltaV = numeric.norm2(numeric.subVV(shortWayTransferVelocities[1], v2))
        longInsertionDeltaV = numeric.norm2(numeric.subVV(longWayTransferVelocities[1], v2))
        if finalOrbitalVelocity?
          shortInsertionDeltaV = injectionDeltaV(finalOrbitalVelocity, shortInsertionDeltaV)
          longInsertionDeltaV = injectionDeltaV(finalOrbitalVelocity, longInsertionDeltaV)
      
      shortDeltaV = shortEjectionDeltaV + shortInsertionDeltaV
      longDeltaV = longEjectionDeltaV + longInsertionDeltaV
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
