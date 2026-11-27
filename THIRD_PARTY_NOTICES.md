# Third-party notices

Diszig is licensed under Apache-2.0. The following third-party components are
selected for use and retain their own licences.

## websocket.zig

Source: https://tangled.org/zzstoatzz.io/websocket.zig

A fork of https://github.com/karlseguin/websocket.zig maintained for Zig 0.17.
Selected revision: tag v0.3.1, commit `34e98f7ee276f94837e6b14e2e291f9db87ba016`.
The client source is vendored under `third_party/websocket/`; that directory's
`VENDOR.md` records the exact files, modifications and the reason the upstream
package manifest can no longer be fetched reproducibly. The MIT text below is
also shipped as `third_party/websocket/LICENSE`.

MIT License

Copyright (c) 2024 Karl Seguin.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## zlib

Source: https://github.com/madler/zlib

Selected revision: tag v1.3.2, pinned by the `zlib` dependency in
`build.zig.zon` to the official release asset and its package hash. Used for
incremental `zlib-stream` inflation and the vendored client's deflate backend.
Not bundled; the build fetches the pinned archive.

Copyright notice:

 (C) 1995-2026 Jean-loup Gailly and Mark Adler

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.

  Jean-loup Gailly        Mark Adler
  jloup@gzip.org          madler@alumni.caltech.edu

## libdave (optional voice)

Source: https://github.com/discord/libdave

Selected revision: tag `v1.3.0/cpp`, commit `b5463c443df74db75a713c775b09a847621e6d62`, MIT.
Not bundled in this source package. Optional voice builds fetch Discord's official
release asset (SHA-256 pinned in `tools/fetch_libdave.py`) and link its C ABI.
The official archive bundles BoringSSL, mlspp and nlohmann-json; their licence texts
are shipped under `packages/voice/licenses/` together with libdave's MIT text.
No libdave binary is distributed by this repository.

An Opus codec is not yet selected; its licence and notice will be added when the
audio phase pins an artifact.

