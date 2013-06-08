/*global numeric: false */

"use strict";

var quaternion = {
    add: numeric.add,
    addeq: numeric.addeq,
    dot: numeric.dot,
    magnitude: numeric.norm2,
    magnitudeSquared: numeric.norm2Squared,
    negate: numeric.negV,
    scale: numeric.mulVS
};

quaternion.conjugate = function(q) {
    return [-q[0], -q[1], -q[2], q[3]];
};

quaternion.normalize = function(q) {
    var s = numeric.norm2(q);
    return numeric.divVS(q, s);
};

quaternion.concat = function(q0, q1) {
    var x0 = q0[0], y0 = q0[1], z0 = q0[2], w0 = q0[3],
        x1 = q1[0], y1 = q1[1], z1 = q1[2], w1 = q1[3],
        result = new Array(4);

    result[0] = w0 * x1 + x0 * w1 + y0 * z1 - z0 * y1;
    result[1] = w0 * y1 - x0 * z1 + y0 * w1 + z0 * x1;
    result[2] = w0 * z1 + x0 * y1 - y0 * x1 + z0 * w1;
    result[3] = w0 * w1 - x0 * x1 - y0 * y1 - z0 * z1;
    return result;
};

quaternion.fromAngleAxis = function(angle, axis) {
    var halfAngle = 0.5 * angle,
        sin = Math.sin(halfAngle);

    axis = quaternion.normalize(axis);
    return quaternion.normalize([sin * axis[0], sin * axis[1], sin * axis[2], Math.cos(halfAngle)]);
};

quaternion.fromVector = function(vec) {
    return [vec[0], vec[1], vec[2], 0];
};

quaternion.toVector = function(q) {
  return [q[0], q[1], q[2]];
}

quaternion.rotate = function(q, vector) {
    var p = quaternion.fromVector(vector);
    return quaternion.toVector(quaternion.concat(quaternion.concat(q, p), quaternion.conjugate(q)));
};
