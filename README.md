# K-force

KRON market discovery, quote calculation, curve buy/sell transaction building,
and graduated KRON V3 pool swaps are implemented in Flutter/Dart. The app also
uses the KasDex L1 Mainnet Pilot API for Launchpad pool discovery and token
deployment. KasDex prepares the launch transactions; K-force verifies the
transaction outputs and Kaspa sighashes, signs locally, and sends the signatures
to KasDex for submission. No WebView or JavaScript/WASM runtime is used.

Wallet Kaspa non-kustodian berbasis Flutter. Seed BIP39 disimpan lokal melalui
`flutter_secure_storage`; node tidak pernah menerima seed atau private key.

## Core yang tersedia

- Pembuatan dan impor frasa pemulihan BIP39 dengan derivasi Schnorr Kaspa pada
  path `m/44'/111111'/0'`.
- Pembacaan aktivitas alamat dari indexer REST mainnet
  `https://api.kaspa.org` dan testnet-10 `https://api-tn10.kaspa.org`.
- Saldo, UTXO, estimasi biaya, dan pengiriman transaksi melalui gRPC. Endpoint
  mainnet bawaan adalah `node.kaspium.io:443` dengan TLS.
- Profil jaringan menerima daftar endpoint gRPC sehingga node publik lain dapat
  dijadikan fallback setelah operator, TLS, dan network ID-nya diverifikasi.
- Endpoint gRPC yang sudah dikonfigurasi dan diuji langsung saat ini hanya
  `node.kaspium.io` mainnet. Testnet-10 belum diaktifkan karena belum ada endpoint
  publik gRPC yang tervalidasi; profil kustom dapat diberikan lewat API.
- Transaksi disusun dan ditandatangani di perangkat. Pemindaian alamat eksternal
  menggunakan gap limit 20 dan indeks receive yang telah diterbitkan disimpan
  aman; UTXO coinbase yang belum matang tidak dipakai.
- Operasi baca node dan permintaan KRON mencoba ulang sekali saat terjadi timeout
  atau kegagalan server sementara. Koneksi gRPC dibuat ulang setelah RPC gagal;
  submit transaksi tidak diulang otomatis jika hasil submit tidak pasti.
- Alamat Terima dibuat dan disimpan lokal sehingga tetap dapat dibuka saat node
  sedang tidak terhubung. Pengiriman tetap memerlukan koneksi mainnet aktif.
- Navigasi utama berurutan Portofolio, Wallet, Launchpad, dan Market.
- Portofolio menggabungkan saldo KAS wallet dengan saldo KCC-20 dari alamat
  wallet melalui indexer KRON.
- Launchpad membaca pool KasDex L1 mainnet dan menyediakan form deploy token
  dengan supply, seed token/KAS, dan periode lock likuiditas.
- Market mempertahankan pasar kurva dan pool KRON, harga dalam KAS, perubahan
  dan volume 24 jam, TVL, holder, grafik candle satu jam, transaksi terbaru,
  serta beli/jual kurva atau swap pool V3. Pilihan provider terpisah menampilkan
  pool KasDex L1 dan mendukung swap KAS/token melalui API KasDex.
- Signing KRON tetap lokal di wallet; setelah PSKT dibangun, aplikasi meminta
  konfirmasi transaksi native sebelum menandatangani input pendanaan wallet dan
  mengirim transaksi ke node Kaspa mainnet.
- Signing launch KasDex juga berlangsung lokal setelah output, tujuan change,
  covenant, biaya, dan seluruh sighash diverifikasi. Signature dikirim ke API
  KasDex; seed dan private key tidak pernah dikirim.
- Daftar pool dan deployment Launchpad menggunakan pilot KasDex L1 mainnet;
  token KasDex yang terdaftar dapat diperdagangkan melalui pilihan KasDex L1 di
  tab Market. Tab Market KRON tetap menggunakan integrasi KRON yang sudah ada.
- Status node backend KasDex diperiksa saat memuat market, dipantau tiap 30
  detik, dan diperiksa kembali sebelum quote/deploy/swap. Jika backend pilot
  terputus, transaksi KasDex dikunci dan error ditampilkan. Node gRPC wallet
  tetap memakai endpoint K-force yang dikonfigurasi (`node.kaspium.io:443`);
  endpoint tersebut tidak menggantikan backend/sequencer KasDex. Provider
  alternatif tidak dipakai tanpa persetujuan pemilik.
- UI native menggunakan palet indigo dan bukan tampilan WebView KRON.

## Menjalankan pemeriksaan

Pasang Flutter 3.44 atau lebih baru dan Dart 3.12 atau lebih baru, lalu jalankan:

```sh
flutter pub get
flutter analyze
flutter test
```

`flutter test` menjalankan tes widget, parsing jumlah, derivasi, parity transaksi,
serta pemeriksaan langsung ke gRPC Kaspium dan API/indexer KRON, sehingga
memerlukan koneksi internet.

Folder Android telah disiapkan. Pembuatan APK memerlukan Android SDK command-line
tools, platform Android, build-tools, NDK, dan lisensi SDK yang telah diterima.
Wallet mencakup alur buat/pulihkan dompet, verifikasi frasa pemulihan, dashboard
saldo, alamat terima dengan QR, pengiriman dengan konfirmasi, dan riwayat transaksi.
Wallet core tetap tersedia sebagai API Dart pada `lib/k_force.dart`.

## Catatan keamanan

K-force menggunakan implementasi protokol wallet Kaspium yang dipatok ke revisi
MIT untuk derivasi, RPC, indeks transaksi, dan signing. Builder KRON native belum
diaudit secara independen dan belum menjalani pengujian transaksi E2E mainnet
dalam sesi ini. Jangan gunakan dana bernilai nyata sebelum audit, review vektor
transaksi terhadap rilis Rusty Kaspa yang berjalan, dan pengujian Android release
dilakukan. Frasa pemulihan harus dicadangkan secara offline oleh pemilik; siapa
pun yang memilikinya dapat menguasai dana.

Node publik dapat mengamati alamat yang diminta. Jangan memasukkan endpoint gRPC
atau indexer yang tidak dipercaya. Deployment KasDex adalah transaksi mainnet
yang tidak dapat dibatalkan; periksa jumlah seed dan lock likuiditas sebelum
menyetujui. API KasDex menerima signature transaksi, sehingga tetap diperlukan
review independen atas kontrak pilot sebelum memakai dana bernilai nyata.
