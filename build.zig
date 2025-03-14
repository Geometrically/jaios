const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options with ARM CPU
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .arm,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm1176jzf_s },
        },
    });

    // Standard optimization options
    const optimize = b.standardOptimizeOption(.{});

    // Create the ELF executable
    const exe = b.addExecutable(.{
        .name = "application.elf",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the assembly file
    exe.addAssemblyFile(b.path("src/mem-barrier.S"));
    exe.addAssemblyFile(b.path("src/start.S"));

    // Add linker script
    exe.setLinkerScriptPath(b.path("memory.ld"));

    // Install the ELF file
    b.installArtifact(exe);

    // Create binary from ELF
    const bin_cmd = b.addSystemCommand(&.{
        "arm-none-eabi-objcopy",
        "-O",
        "binary",
        b.getInstallPath(.bin, "application.elf"),
        b.getInstallPath(.bin, "application.bin"),
    });
    bin_cmd.step.dependOn(b.getInstallStep());

    // Create disassembly listing
    const elf_path = b.getInstallPath(.bin, "application.elf");
    const list_path = b.getInstallPath(.bin, "application.list");

    const list_cmd = b.addSystemCommand(&.{
        "bash",
        "-c",
        "arm-none-eabi-objdump -d \"$1\" > \"$2\"",
        "--",
        elf_path,
        list_path,
    });
    list_cmd.step.dependOn(b.getInstallStep());

    // // Install to Pi
    const pi_cmd = b.addSystemCommand(&.{
        "./bin/pi-install",
        b.getInstallPath(.bin, "application.bin"),
    });
    pi_cmd.step.dependOn(&bin_cmd.step);

    // // Create a custom step for the entire build process
    const build_pi_step = b.step("pi", "Build and install to Pi");
    build_pi_step.dependOn(&pi_cmd.step);
    build_pi_step.dependOn(&list_cmd.step);
}
