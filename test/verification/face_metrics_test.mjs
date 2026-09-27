import test from 'node:test';
import assert from 'node:assert/strict';
import {faceMetrics} from '../../web/face/metrics.mjs';
function face({yaw=0,tilt=0,aspect=4/3,eyeWidth=.3}={}) {
  const points = Array.from({length:478},() => ({x:.5,y:.5}));
  points[33]={x:.5-eyeWidth/2,y:.4}; points[263]={x:.5+eyeWidth/2,y:.4};
  points[1]={x:.5+yaw*eyeWidth,y:.5};
  points[10]={x:.5,y:.2}; points[152]={x:.5,y:.8};
  points[234]={x:.25,y:.5}; points[454]={x:.75,y:.5};
  for (const p of points) {
    const x=(p.x-.5)*aspect,y=p.y-.5;
    p.x=.5+(x*Math.cos(tilt)-y*Math.sin(tilt))/aspect;
    p.y=.5+x*Math.sin(tilt)+y*Math.cos(tilt);
  }
  return {faceLandmarks:[points],faceBlendshapes:[{categories:[
    {categoryName:'eyeBlinkLeft',score:.1},{categoryName:'eyeBlinkRight',score:.15}]}]};
}
test('left/right direction and magnitude survive head tilt and portrait/landscape frames',()=>{
  for (const aspect of [3/4,4/3,16/9]) for (const yaw of [-.3,0,.3]) for (const tilt of [-.2,0,.2]) {
    const sample=faceMetrics(face({aspect,yaw,tilt}),aspect);
    assert.ok(Math.abs(sample.yaw-yaw)<1e-8);
    assert.equal(sample.centered,true);
  }
});
test('a visible turned face is not rejected just because eye spacing shrinks',()=>{
  assert.equal(faceMetrics(face({eyeWidth:.09,yaw:.3})).centered,true);
});
test('absent, multiple, invalid or clipped landmarks cannot pass framing',()=>{
  assert.equal(faceMetrics({}).centered,false);
  const result=face(); result.faceLandmarks.push(result.faceLandmarks[0]);
  assert.equal(faceMetrics(result).count,2);
  for (const bad of [NaN,Infinity,-.1,1.1]) {
    const result=face(); result.faceLandmarks[0][10].x=bad;
    assert.equal(faceMetrics(result).centered,false);
  }
});
test('absent eye scores do not count as open eyes',()=>{
  const result=face(); result.faceBlendshapes=[];
  assert.ok(Number.isNaN(faceMetrics(result).blink));
});
