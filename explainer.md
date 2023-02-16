# WebXR/WebGPU binding

WebXR is well understood to be a demanding API in terms of graphics rendering performance, a task that has previously fallen entirely to WebGL. The [WebGL API](https://www.khronos.org/registry/webgl/specs/latest/1.0/), while capable, is based on the relatively outdated native APIs which have recently been overtaken by more modern equivalents. As a result, it can sometimes be a struggle to implement various recommended XR rendering techniques in a performant way.

The [WebGPU API](https://gpuweb.github.io/gpuweb/) is an upcoming API for utilizing the graphics and compute capabilities of a device's GPU more efficiently than WebGL allows, with an API that better matches both GPU hardware architecture and the modern native APIs that interface with them, such as Vulkan, Direct3D 12, and Metal. As it offers the potential to enable developers to get significantly better performance in their WebXR applications.

This module aims to allow the existing [WebXR Layers module](https://immersive-web.github.io/layers/) to interface with WebGPU by providing WebGPU swap chains for each layer type.

## WebGPU binding

As with the existing WebGL path described in the Layers module, all WebGPU resources required by WebXR would be supplied by an `XRGPUBinding` instance, created with an `XRSession` and [`GPUDevice`](https://gpuweb.github.io/gpuweb/#gpu-device) like so:

```js
const gpuAdapter = await navigator.gpu.getAdapter({xrCompatible: true});
const gpuDevice = await gpuAdapter.requestDevice();
const xrGpuBinding = new XRGPUBinding(xrSession, gpuDevice);
```

Note that the [`GPUAdapter`](https://gpuweb.github.io/gpuweb/#gpu-adapter) must be requested with the `xrCompatible` option set to `true`. This mirrors the WebGL context creation arg by the same name, and ensures that the returned adapter will be one that is compatible with the UAs selected XR Device.

Once the `XRGPUBinding` instance has been created, it can be used to create the various `XRCompositorLayer`s, just like `XRWebGLBinding`.

```js
const gpuAdapter = await navigator.gpu.getAdapter({xrCompatible: true});
const gpuDevice = await gpuAdapter.requestDevice();
const xrGpuBinding = new XRGPUBinding(xrSession, gpuDevice);
const projectionLayer = xrGpuBinding.createProjectionLayer();
```

This allocates a layer that supplies a [`GPUTexture`](https://gpuweb.github.io/gpuweb/#gputexture) to use for color attachments. The color format of the layer can be specified if desired, and if depth/stencil is required it can be requested as well by specifying an appropriate depth/stencil format. The list of supported formats is given by the `XRGPUBinding.supportedColorFormats` and `XRGPUBinding.supportedDepthStencilFormats` attributes, which list the supported formats in order of preference (so element `0` in the is always the most highly preferred format.)

```js
const gpuAdapter = await navigator.gpu.getAdapter({xrCompatible: true});
const gpuDevice = await gpuAdapter.requestDevice();
const xrGpuBinding = new XRGPUBinding(xrSession, gpuDevice);
const projectionLayer = xrGpuBinding.createProjectionLayer({
  colorFormat: xrGpuBinding.supportedColorFormats[0],
  depthStencilFormat: xrGpuBinding.supportedDepthStencilFormats[0],
});
```

This allocates a layer that supplies a [`GPUTexture`](https://gpuweb.github.io/gpuweb/#gputexture) to use for both color attachments and depth/stencil attachements. Note that if a `depthStencilFormat` is provided it is implied that the application will populate it will a reasonable representation of the scene's depth and that the UAs XR compositor may use that information when rendering. If you cannot guarantee that the the depth information output by your application is representative of the scene rendered into the color attachment your application should allocate it's own depth/stencil textures instead.

As with the base XR Layers module, `XRGPUBinding` is only required to support `XRProjectionLayer`s unless the `layers` feature descriptor is supplied at session creation and supported by the UA/device. If the `layers` feature descriptor is requested and supported, however, all other `XRCompositionLayer` types must be supported. Layers are still set via `XRSession`'s `updateRenderState` method, as usual:

```js
const quadLayer = xrGpuBinding.createQuadLayer({
  space: xrReferenceSpace,
  viewPixelWidth: 1024,
  viewPixelHeight: 768,
  layout: 'stereo'
});

xrSession.updateRenderState({ layers: [projectionLayer, quadLayer] });
```

## Rendering

During `XRFrame` processing each layer can be updated with new imagery. Calling `getViewSubImage()` with a view from the `XRFrame` will return an `XRGPUSubImage` indicating the textures to use as the render target and what portion of the texture will be presented to the `XRView`'s associated physical display.

WebGPU projection layers will provide the same `colorTexture` and `depthStencilTexture` for each `GPUSubImage` queried, while the `GPUSubImage` queried for each `XRView` will contian a different `GPUTextureViewDescriptor` that should be used when creating the texture views of both the color and depth textures to use as render pass attachments. The `GPUSubImage`'s `viewport` must also be set to ensure only the expected portion of the texture is written to.

```js
// Render Loop for a projection layer with a WebGPU texture source.
const xrGpuBinding = new XRGPUBinding(xrSession, gpuDevice);
const layer = xrGpuBinding.createProjectionLayer({
  colorFormat: xrGpuBinding.supportedColorFormats[0],
  depthStencilFormat: xrGpuBinding.supportedDepthStencilFormats[0],
});

xrSession.updateRenderState({ layers: [layer] });
xrSession.requestAnimationFrame(onXRFrame);

function onXRFrame(time, xrFrame) {
  xrSession.requestAnimationFrame(onXRFrame);

  const commandEncoder = device.createCommandEncoder({});

  for (const view in xrViewerPose.views) {
    const subImage = xrGpuBinding.getViewSubImage(layer, view);

    // Render to the subImage's color and depth textures
    const passEncoder = commandEncoder.beginRenderPass({
        colorAttachments: [{
          attachment: subImage.colorTexture.createView(subImage.viewDescriptor),
          loadOp: 'clear',
          clearValue: [0,0,0,1],
        }],
        depthStencilAttachment: {
          attachment: subImage.depthStencilTexture.createView(subImage.viewDescriptor),
          depthLoadOp: 'clear',
          depthClearValue: 1.0,
          depthStoreOp: 'store',
          stencilLoadOp: 'clear',
          stencilClearValue: 0,
          stencilStoreOp: 'store',
        }
      });

    let vp = subImage.viewport;
    passEncoder.setViewport(vp.x, vp.y, vp.width, vp.height, 0.0, 1.0);

    // Render from the viewpoint of xrView

    passEncoder.endPass();
  }

  device.defaultQueue.submit([commandEncoder.finish()]);
}
```

Non-projection layers, such as `XRQuadLayer`, may only have 1 sub image for `'mono'` layers and 2 sub images for `'stereo'` layers, which may not align exactly with the number of `XRView`s reported by the device. To avoid rendering the same view multiple times in these scenarios Non-projection layers must use  the `XRGPUBinding`'s `getSubImage()` method to get the `XRSubImage` to render to.

For mono textures the `XRSubImage` can be queried using just the layer and `XRFrame`:

```js
// Render Loop for a projection layer with a WebGPU texture source.
const xrGpuBinding = new XRGPUBinding(xrSession, gpuDevice);
const quadLayer = xrGpuBinding.createQuadLayer({
  space: xrReferenceSpace,
  viewPixelWidth: 512,
  viewPixelHeight: 512,
  layout: 'mono'
});

// Position 2 meters away from the origin with a width and height of 1.5 meters
quadLayer.transform = new XRRigidTransform({z: -2});
quadLayer.width = 1.5;
quadLayer.height = 1.5;

xrSession.updateRenderState({ layers: [quadLayer] });
xrSession.requestAnimationFrame(onXRFrame);

function onXRFrame(time, xrFrame) {
  xrSession.requestAnimationFrame(onXRFrame);

  const commandEncoder = device.createCommandEncoder({});

  const subImage = xrGpuBinding.getSubImage(quadLayer, xrFrame);

  // Render to the subImage's color texture.
  const passEncoder = commandEncoder.beginRenderPass({
      colorAttachments: [{
        attachment: subImage.colorTexture.createView(subImage.viewDescriptor),
        loadOp: 'clear',
        clearValue: [0,0,0,0],
      }]
      // Many times simple quad layers won't require a depth attachment, as they're often just
      // displaying a pre-rendered 2D image.
    });

  let vp = subImage.viewport;
  passEncoder.setViewport(vp.x, vp.y, vp.width, vp.height, 0.0, 1.0);

  // Render the mono content.

  passEncoder.endPass();

  device.defaultQueue.submit([commandEncoder.finish()]);
}
```

For stereo textures the target `XREye` must be given to `getSubImage()` as well:

```js
// Render Loop for a projection layer with a WebGPU texture source.
const xrGpuBinding = new XRGPUBinding(xrSession, gpuDevice);
const quadLayer = xrGpuBinding.createQuadLayer({
  space: xrReferenceSpace,
  viewPixelWidth: 512,
  viewPixelHeight: 512,
  layout: 'stereo'
});

// Position 2 meters away from the origin with a width and height of 1.5 meters
quadLayer.transform = new XRRigidTransform({z: -2});
quadLayer.width = 1.5;
quadLayer.height = 1.5;

xrSession.updateRenderState({ layers: [quadLayer] });
xrSession.requestAnimationFrame(onXRFrame);

function onXRFrame(time, xrFrame) {
  xrSession.requestAnimationFrame(onXRFrame);

  const commandEncoder = device.createCommandEncoder({});

  for (const eye of ['left', 'right']) {
    const subImage = xrGpuBinding.getSubImage(quadLayer, xrFrame, eye);

    // Render to the subImage's color texture.
    const passEncoder = commandEncoder.beginRenderPass({
        colorAttachments: [{
          attachment: subImage.colorTexture.createView(subImage.viewDescriptor),
          loadOp: 'clear',
          clearValue: [0,0,0,0],
        }]
        // Many times simple quad layers won't require a depth attachment, as they're often just
        // displaying a pre-rendered 2D image.
      });

    let vp = subImage.viewport;
    passEncoder.setViewport(vp.x, vp.y, vp.width, vp.height, 0.0, 1.0);

    // Render content for the given eye.

    passEncoder.endPass();
  }

  device.defaultQueue.submit([commandEncoder.finish()]);
}
```

## Proposed IDL

```webidl
partial dictionary GPURequestAdapterOptions {
    boolean xrCompatible = false;
};

[Exposed=Window] interface XRGPUSubImage : XRSubImage {
  [SameObject] readonly attribute GPUTexture colorTexture;
  [SameObject] readonly attribute GPUTexture? depthStencilTexture;
  readonly attribute GPUTextureViewDescriptor viewDescriptor;
  readonly attribute unsigned long textureWidth;
  readonly attribute unsigned long textureHeight;
  readonly attribute unsigned long textureArrayLayers;
};

dictionary XRGPUProjectionLayerInit {
  GPUTextureFormat colorFormat = "bgra8unorm";
  GPUTextureFormat? depthStencilFormat;
  GPUTextureUsageFlags textureUsage = 0x10; // GPUTextureUsage.OUTPUT_ATTACHMENT
  double scaleFactor = 1.0;
};

dictionary XRGPULayerInit {
  GPUTextureFormat colorFormat = "bgra8unorm";
  GPUTextureFormat? depthStencilFormat;
  GPUTextureUsageFlags textureUsage = 0x10; // GPUTextureUsage.OUTPUT_ATTACHMENT
  required XRSpace space;
  required unsigned long viewPixelWidth;
  required unsigned long viewPixelHeight;
  XRLayerLayout layout = "mono";
  boolean isStatic = false;
};

dictionary XRGPUQuadLayerInit : XRGPULayerInit {
  XRRigidTransform? transform;
  float width = 1.0;
  float height = 1.0;
};

dictionary XRGPUCylinderLayerInit : XRGPULayerInit {
  XRRigidTransform? transform;
  float radius = 2.0;
  float centralAngle = 0.78539;
  float aspectRatio = 2.0;
};

dictionary XRGPUEquirectLayerInit : XRGPULayerInit {
  XRRigidTransform? transform;
  float radius = 0;
  float centralHorizontalAngle = 6.28318;
  float upperVerticalAngle = 1.570795;
  float lowerVerticalAngle = -1.570795;
};

dictionary XRGPUCubeLayerInit : XRGPULayerInit {
  DOMPointReadOnly? orientation;
};

[Exposed=Window] interface XRGPUBinding {
  constructor(XRSession session, GPUDevice device);

  readonly attribute double nativeProjectionScaleFactor;

  readonly attribute FrozenArray<GPUTextureFormat> supportedColorFormats;
  readonly attribute FrozenArray<GPUTextureFormat> supportedDepthStencilFormats;

  XRProjectionLayer createProjectionLayer(optional XRGPUProjectionLayerInit init);
  XRQuadLayer createQuadLayer(optional XRGPUQuadLayerInit init);
  XRCylinderLayer createCylinderLayer(optional XRGPUCylinderLayerInit init);
  XREquirectLayer createEquirectLayer(optional XRGPUEquirectLayerInit init);
  XRCubeLayer createCubeLayer(optional XRGPUCubeLayerInit init);

  XRGPUSubImage getSubImage(XRCompositionLayer layer, XRFrame frame, optional XREye eye = "none");
  XRGPUSubImage getViewSubImage(XRProjectionLayer layer, XRView view);
};
```
