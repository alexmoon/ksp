importScripts('numeric-1.2.6.min.js')
importScripts('quaternion.js')
importScripts('lambert.js')
importScripts('orbit.js')

WIDTH = 300
HEIGHT = 300

@onmessage = (event) ->
  transferType = event.data.transferType
  originOrbit = Orbit.fromJSON(event.data.originOrbit)
  initialOrbitalVelocity = event.data.initialOrbitalVelocity
  destinationOrbit = Orbit.fromJSON(event.data.destinationOrbit)
  finalOrbitalVelocity = event.data.finalOrbitalVelocity
  earliestDeparture = event.data.earliestDeparture
  shortestTimeOfFlight = event.data.shortestTimeOfFlight
  xResolution = event.data.xScale / WIDTH
  yResolution = event.data.yScale / HEIGHT
  referenceBody = originOrbit.referenceBody
  
  n1 = originOrbit.normalVector()
  
  # Pre-calculate destination positions and velocities
  originPositions = []
  originVelocities = []
  for x in [0...WIDTH]
    departureTime = earliestDeparture + x * xResolution
    trueAnomaly = originOrbit.trueAnomalyAt(departureTime)
    originPositions[x] = originOrbit.positionAtTrueAnomaly(trueAnomaly)
    originVelocities[x] = originOrbit.velocityAtTrueAnomaly(trueAnomaly)
  
  deltaVs = new Float64Array(WIDTH * HEIGHT)
  i = 0
  minDeltaV = Infinity
  maxDeltaV = 0
  lastProgress = 0
  for y in [0...HEIGHT]
    timeOfFlight = shortestTimeOfFlight + ((HEIGHT-1) - y) * yResolution
    
    for x in [0...WIDTH]
      departureTime = earliestDeparture + x * xResolution
      arrivalTime = departureTime + timeOfFlight
      
      p1 = originPositions[x]
      v1 = originVelocities[x]
      
      trueAnomaly = destinationOrbit.trueAnomalyAt(arrivalTime)
      p2 = destinationOrbit.positionAtTrueAnomaly(trueAnomaly)
      v2 = destinationOrbit.velocityAtTrueAnomaly(trueAnomaly)
  
      transfer = Orbit.transfer(transferType, referenceBody, departureTime, p1, v1, n1, arrivalTime, p2, v2, initialOrbitalVelocity, finalOrbitalVelocity)
      deltaVs[i++] = deltaV = transfer.deltaV

      if deltaV < minDeltaV
        minDeltaV = deltaV
        minDeltaVPoint = { x: x, y: y }
      
      maxDeltaV = Math.max(deltaV, maxDeltaV)
    
    now = Date.now()
    if now - lastProgress > 100
      postMessage(progress: (y + 1) / HEIGHT)
      lastProgress = now
  
  try
    # Try to use transferable objects first to save about 1 MB memcpy
    postMessage({ deltaVs: deltaVs.buffer, minDeltaV: minDeltaV, minDeltaVPoint: minDeltaVPoint, maxDeltaV: maxDeltaV }, [deltaVs.buffer])
  catch error
    # Fallback to compatible version
    postMessage({ deltaVs: deltaVs, minDeltaV: minDeltaV, minDeltaVPoint: minDeltaVPoint, maxDeltaV: maxDeltaV })
