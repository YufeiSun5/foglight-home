# Confirmed local sampler diagnosis

See `art_source/diagnostics/BLACK_SPECKLE_DIAGNOSIS.md` and `black_speckle_evidence.json` for the complete controlled comparison and frame hashes.

On this Godot 4.6.3 GL Compatibility + Mesa llvmpipe cloud renderer, anisotropic filtering produced dark speckles on curved surfaces with singular UV derivatives. Changing only the material sampling to LINEAR_WITH_MIPMAPS removed the spots in a native frame. Roof, flywheel, canopy and cart-wheel sampled exact-black counts fell to zero. The material remains native StandardMaterial3D with its original PBR maps and parameters; no custom color remapping was introduced.

UV degeneracy and malformed tangent frames are genuine source defects. Tangent repair alone did not cure the artifact, and source UV repair remains necessary before production asset acceptance. This result is not proof of a driver bug on every GPU/backend.

Failed diagnostics and their source snapshots remain under `.qa/`. The final r3 native frame restores the sun's actual shadows and uses ordinary linear+mipmap sampling, 4x MSAA and 2x internal 3D resolution.
