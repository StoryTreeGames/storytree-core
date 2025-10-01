const std = @import("std");
const wgpu = @import("wgpu");
const core = @import("storytree-core");

const log = @import("std").log.scoped(.wgpu);

const Renderer = @This();

surface: *wgpu.Surface,
device: *wgpu.Device,
queue: *wgpu.Queue,
surface_config: wgpu.SurfaceConfiguration,
pipeline: *wgpu.RenderPipeline,

width: u32 = 0,
height: u32 = 0,
resizeWidth: u32 = 0,
resizeHeight: u32 = 0,

pub fn create(window: *core.window.Window) !Renderer {
    var self: Renderer = undefined;

    const instance = wgpu.Instance.create(null) orelse return error.CouldNotCreateInstance;
    defer instance.release();

    log.info("creating surface", .{});
    const handles = window.handles();
    self.surface = instance.createSurface(&switch (@import("builtin").os.tag) {
        .windows => wgpu.surfaceDescriptorFromWindowsHWND(.{
            .label = "HWND_surface",
            .hinstance = handles.parent,
            .hwnd = handles.target,
        }),
        .linux => wgpu.surfaceDescriptorFromWaylandSurface(.{
            .label = "HWND_surface",
            .display = handles.parent,
            .surface = handles.target,
        }),
        else => @compileError("platform not supported"),
    }) orelse return error.CouldNotCreateSurface;

    log.info("fetching adapter", .{});
    const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
        .compatible_surface = self.surface,
    }, std.time.ns_per_ms);
    const adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.AdapterRequestFailed,
    };
    defer adapter.release();

    log.info("fetching device", .{});
    const device_request = adapter.requestDeviceSync(&wgpu.DeviceDescriptor{
        .required_limits = null,
    });
    self.device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.DeviceRequestFailed,
    };

    log.info("create queue", .{});
    self.queue = self.device.getQueue() orelse return error.CouldNotGetQueue;

    log.info("create capabilities", .{});
    var surface_capabilities: wgpu.SurfaceCapabilities = undefined;
    self.surface.getCapabilities(adapter, &surface_capabilities);

    log.info("configuring surface", .{});
    const rect = window.getClientRect();
    self.width = rect.width;
    self.height = rect.height;
    self.resizeWidth = rect.width;
    self.resizeHeight = rect.height;
    self.surface_config = wgpu.SurfaceConfiguration{
        .width = rect.width,
        .height = rect.height,
        .format = surface_capabilities.formats[0],
        .device = self.device,
    };

    self.surface.configure(&self.surface_config);

    // Render pipeline stuff
    // -------------------------------------------------------------------------
    log.info("load shader module", .{});
    const shader_module = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./shader.wgsl"),
    })) orelse return error.CouldNotCreateShader;
    defer shader_module.release();

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = self.surface_config.format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{
                    .operation = wgpu.BlendOperation.add,
                    .src_factor = wgpu.BlendFactor.src_alpha,
                    .dst_factor = wgpu.BlendFactor.one_minus_src_alpha,
                },
                .alpha = wgpu.BlendComponent{
                    .operation = wgpu.BlendOperation.add,
                    .src_factor = wgpu.BlendFactor.zero,
                    .dst_factor = wgpu.BlendFactor.one,
                },
            },
        },
    };

    log.info("create pipeline", .{});
    self.pipeline = self.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = "vs_main",
        },
        .primitive = wgpu.PrimitiveState{},
        .multisample = wgpu.MultisampleState{},
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = "fs_main",
            .target_count = color_targets.len,
            .targets = color_targets.ptr,
        },
    }) orelse return error.CouldNotCreateRenderPipeline;

    log.info("finished renderer setup", .{});
    return self;
}

pub fn resize(self: *Renderer, w: u32, h: u32) void {
    log.info("resize surface {d} x {d}", .{ w, h });
    self.resizeWidth = w;
    self.resizeHeight = h;
}

pub fn render(self: *Renderer) !void {
    if (self.width != self.resizeWidth or self.height != self.resizeHeight) {
        self.width = self.resizeWidth;
        self.height = self.resizeHeight;

        self.surface_config.width = @max(self.width, 1);
        self.surface_config.height = @max(self.height, 1);
        self.surface.configure(&self.surface_config);
    }

    var surface_texture: wgpu.SurfaceTexture = undefined;
    self.surface.getCurrentTexture(&surface_texture);
    if (surface_texture.status != wgpu.GetCurrentTextureStatus.success) {
        return error.SurfaceTextureNotSuccessfulStatus; // TODO: find a better name for that
    }

    const target_view = surface_texture.texture.createView(&wgpu.TextureViewDescriptor{
        .label = "surface texture view",
        .format = surface_texture.texture.getFormat(),
        .dimension = wgpu.ViewDimension.@"2d",
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return error.CouldNotCreateTextureView;

    const encoder = self.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{ .label = "render command encoder" }) orelse return error.CouldNotCreateCommandEncoder;

    const render_pass_color_attachments = &[_]wgpu.ColorAttachment{
        wgpu.ColorAttachment{
            .view = target_view,
            .clear_value = wgpu.Color{ .r = 0.62, .g = 0.83, .b = 0.64, .a = 0.0 },
        },
    };

    const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
        .color_attachment_count = render_pass_color_attachments.len,
        .color_attachments = render_pass_color_attachments.ptr,
    }) orelse return error.CouldNotBeginRenderPass;

    render_pass.setPipeline(self.pipeline);
    render_pass.draw(3, 1, 0, 0);
    render_pass.end();
    render_pass.release();

    const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
        .label = "render command buffer",
    }) orelse return error.CouldNotFinishCommandEncoder;
    const commands = [_]*const wgpu.CommandBuffer{
        command_buffer,
    };
    encoder.release();

    self.queue.submit(&commands);

    command_buffer.release();
    target_view.release();

    self.surface.present();

    _ = self.device.poll(false, null);
}

pub fn release(self: *Renderer) void {
    self.pipeline.release();
    self.surface.unconfigure();
    self.queue.release();
    self.surface.release();
    self.device.release();
}
