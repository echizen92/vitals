# Third-party notices: Vitals Companion for Mac

Vitals Companion is GPL-3.0-or-later (`LICENSE`). The downloadable app bundles a Python runtime and the
packages below, unmodified, in `Contents/Resources/python`. Licence texts are inside the app at the paths
listed (under `Contents/Resources/python/lib/python3.13/site-packages/`). The GPL source offer is in
`companion/README.md`.

## Python runtime

CPython 3.13.18, built by python-build-standalone (astral-sh, release 20261026,
`cpython-3.13.18+20261026-aarch64-apple-darwin-install_only_stripped`). Licence: PSF-2.0 (Python Software Foundation
License); full text in `Contents/Resources/python/lib/python3.13/LICENSE.txt`, which also carries the licences of
the third-party code inside CPython itself.

Libraries python-build-standalone builds into that runtime, according to its documentation: OpenSSL (Apache-2.0),
libffi (MIT), SQLite (public domain), XZ Utils / liblzma (0BSD), zlib (Zlib), bzip2 (bzip2-1.0.6),
mpdecimal (BSD-2-Clause), ncurses (X11 / MIT), libedit (BSD-3-Clause), Tcl/Tk (TCL). Source:
https://github.com/astral-sh/python-build-standalone

## Python packages (91)

| Package | Version | Licence | Source | Licence files |
|---|---|---|---|---|
| aiofiles | 25.1.0 | Apache-2.0 | https://github.com/Tinche/aiofiles | `aiofiles-25.1.0.dist-info/licenses/LICENSE`, `aiofiles-25.1.0.dist-info/licenses/NOTICE` |
| annotated-doc | 0.0.7 | MIT | https://github.com/fastapi/annotated-doc | `annotated_doc-0.0.7.dist-info/licenses/LICENSE` |
| annotated-types | 0.8.0 | MIT | https://github.com/annotated-types/annotated-types | `annotated_types-0.8.0.dist-info/licenses/LICENSE` |
| ansilogs | 1.2.0 | MIT License | https://github.com/doronz88/ansilogs | `ansilogs-1.2.0.dist-info/licenses/LICENSE` |
| anyio | 4.16.0 | MIT | https://github.com/agronholm/anyio | `anyio-4.16.0.dist-info/licenses/LICENSE` |
| apple-compress | 0.2.3 | MIT (from its licence file) |  | `apple_compress-0.2.3.dist-info/LICENSE` |
| arrow | 1.4.0 | Apache Software License | https://github.com/arrow-py/arrow | `arrow-1.4.0.dist-info/licenses/LICENSE` |
| ASGIMiddlewareStaticFile | 0.7.0 | MIT (from its licence file) | https://github.com/rexzhang/asgi-middleware-static-file | `asgimiddlewarestaticfile-0.7.0.dist-info/licenses/LICENSE` |
| asgiref | 3.13.0 | BSD-3-Clause | https://github.com/django/asgiref/ | `asgiref-3.13.0.dist-info/licenses/LICENSE` |
| ASGIWebDAV | 2.3.0 | MIT (from its licence file) | https://github.com/rexzhang/asgi-webdav | `asgiwebdav-2.3.0.dist-info/licenses/LICENSE` |
| asn1 | 2.8.0 | BSD | https://github.com/andrivet/python-asn1 | `asn1-2.8.0.dist-info/LICENSE` |
| asttokens | 3.0.2 | Apache 2.0 | https://github.com/gristlabs/asttokens | `asttokens-3.0.2.dist-info/licenses/LICENSE` |
| backports.zstd | 1.8.0 | PSF-2.0 | https://github.com/rogdham/backports.zstd | `backports_zstd-1.8.0.dist-info/licenses/LICENSE.txt`, `backports_zstd-1.8.0.dist-info/licenses/LICENSE_zstd.txt` |
| bpylist2 | 4.1.1 | MIT | https://github.com/parabolala/bpylist2 |  |
| bytestruct | 0.2.0 | MIT | https://github.com/doronz88/bytestruct | `bytestruct-0.2.0.dist-info/licenses/LICENSE` |
| certifi | 2026.10.23 | MPL-2.0 | https://github.com/certifi/python-certifi | `certifi-2026.10.23.dist-info/licenses/LICENSE` |
| cffi | 2.1.1 | MIT-0 | https://github.com/python-cffi/cffi | `cffi-2.1.1.dist-info/licenses/LICENSE` |
| chardet | 7.7.0 | 0BSD | https://github.com/chardet/chardet | `chardet-7.7.0.dist-info/licenses/LICENSE` |
| charset-normalizer | 3.5.2 | MIT | https://github.com/jawah/charset_normalizer | `charset_normalizer-3.5.2.dist-info/licenses/LICENSE` |
| click | 8.5.1 | BSD-3-Clause | https://github.com/pallets/click/ | `click-8.5.1.dist-info/licenses/LICENSE.txt` |
| construct | 2.10.70 | MIT | https://github.com/construct/construct | `construct-2.10.70.dist-info/LICENSE` |
| cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause | https://github.com/pyca/cryptography | `cryptography-50.0.2.dist-info/licenses/LICENSE`, `cryptography-50.0.2.dist-info/licenses/LICENSE.APACHE`, `cryptography-50.0.2.dist-info/licenses/LICENSE.BSD` |
| daemonize | 2.5.0 | MIT | https://github.com/thesharp/daemonize | `daemonize-2.5.0.dist-info/LICENSE` |
| dataclass-wizard | 1.0.0 | Apache Software License | https://github.com/rnag/dataclass-wizard | `dataclass_wizard-1.0.0.dist-info/licenses/LICENSE` |
| defusedxml | 0.7.1 | PSFL | https://github.com/tiran/defusedxml | `defusedxml-0.7.1.dist-info/LICENSE` |
| developer_disk_image | 0.3.0 | GNU General Public License v3 or later (GPLv3+) | https://github.com/doronz88/DeveloperDiskImage |  |
| enum-compat | 0.0.3 | MIT | https://github.com/jstasiak/enum-compat |  |
| executing | 2.3.0 | MIT | https://github.com/alexmojaki/executing | `executing-2.3.0.dist-info/licenses/LICENSE.txt` |
| fastapi | 0.164.0 | MIT | https://github.com/fastapi/fastapi | `fastapi-0.164.0.dist-info/licenses/LICENSE` |
| h11 | 0.16.0 | MIT | https://github.com/python-hyper/h11 | `h11-0.16.0.dist-info/licenses/LICENSE.txt` |
| hyperframe | 6.1.0 | MIT License | https://github.com/python-hyper/hyperframe/ | `hyperframe-6.1.0.dist-info/LICENSE` |
| idna | 3.20 | BSD-3-Clause | https://github.com/kjd/idna | `idna-3.20.dist-info/licenses/LICENSE.md` |
| ifaddr | 0.2.0 | MIT | https://github.com/pydron/ifaddr | `ifaddr-0.2.0.dist-info/LICENSE.txt` |
| ioregistry | 0.0.6 | GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007 | https://github.com/doronz88/ioregistry | `ioregistry-0.0.6.dist-info/licenses/LICENSE` |
| ipsw-parser | 1.9.1 | GNU General Public License v3 or later (GPLv3+) | https://github.com/doronz88/ipsw_parser | `ipsw_parser-1.9.1.dist-info/licenses/LICENSE` |
| ipython | 9.18.1 | BSD-3-Clause | https://ipython.org | `ipython-9.18.1.dist-info/licenses/COPYING.rst`, `ipython-9.18.1.dist-info/licenses/LICENSE` |
| ipython_pygments_lexers | 1.1.1 | BSD License | https://github.com/ipython/ipython-pygments-lexers | `ipython_pygments_lexers-1.1.1.dist-info/LICENSE` |
| jedi | 0.20.1 | MIT | https://github.com/davidhalter/jedi | `jedi-0.20.1.dist-info/LICENSE.txt`, `jedi/third_party/django-stubs/LICENSE.txt`, `jedi/third_party/typeshed/LICENSE` |
| loguru | 0.7.3 | MIT License | https://github.com/Delgan/loguru |  |
| markdown-it-py | 4.3.0 | MIT License | https://github.com/executablebooks/markdown-it-py | `markdown_it_py-4.3.0.dist-info/licenses/LICENSE`, `markdown_it_py-4.3.0.dist-info/licenses/LICENSE.markdown-it` |
| matplotlib-inline | 0.2.2 | BSD-3-Clause | https://github.com/ipython/matplotlib-inline | `matplotlib_inline-0.2.2.dist-info/licenses/LICENSE` |
| mdurl | 0.1.2 | MIT License | https://github.com/executablebooks/mdurl | `mdurl-0.1.2.dist-info/LICENSE` |
| opack2 | 0.2.0 | GNU General Public License v3 or later (GPLv3+) | https://github.com/doronz88/opack2 | `opack2-0.2.0.dist-info/licenses/LICENSE` |
| opentelemetry-api | 1.45.2 | Apache-2.0 | https://github.com/open-telemetry/opentelemetry-python/tree/main/opentelemetry-api | `opentelemetry_api-1.45.2.dist-info/licenses/LICENSE` |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | https://github.com/pypa/packaging | `packaging-26.3.dist-info/licenses/LICENSE`, `packaging-26.3.dist-info/licenses/LICENSE.APACHE`, `packaging-26.3.dist-info/licenses/LICENSE.BSD` |
| parso | 0.8.7 | MIT | https://github.com/davidhalter/parso | `parso-0.8.7.dist-info/LICENSE.txt` |
| pexpect | 4.9.0 | ISC license | https://github.com/pexpect/pexpect | `pexpect-4.9.0.dist-info/LICENSE` |
| pillow | 13.0.0 | MIT-CMU | https://python-pillow.org | `pillow-13.0.0.dist-info/licenses/LICENSE` |
| pmd-net-addr | 0.0.3 | GPL-3.0-or-later | https://github.com/ccie18643/PyTCP | `pmd_net_addr-0.0.3.dist-info/licenses/LICENSE` |
| pmd-net-proto | 0.0.3 | GPL-3.0-or-later | https://github.com/ccie18643/PyTCP | `pmd_net_proto-0.0.3.dist-info/licenses/LICENSE` |
| pmd-pytcp | 0.3.9 | GPL-3.0-or-later | https://github.com/ccie18643/PyTCP | `pmd_pytcp-0.3.9.dist-info/licenses/LICENSE` |
| prompt_toolkit | 3.0.53 | BSD License | https://github.com/prompt-toolkit/python-prompt-toolkit | `prompt_toolkit-3.0.53.dist-info/licenses/AUTHORS.rst`, `prompt_toolkit-3.0.53.dist-info/licenses/LICENSE` |
| psutil | 7.2.2 | BSD-3-Clause | https://github.com/giampaolo/psutil | `psutil-7.2.2.dist-info/LICENSE` |
| ptyprocess | 0.7.0 | UNKNOWN | https://github.com/pexpect/ptyprocess | `ptyprocess-0.7.0.dist-info/LICENSE` |
| pure_eval | 0.2.4 | MIT | http://github.com/alexmojaki/pure_eval | `pure_eval-0.2.4.dist-info/licenses/LICENSE.txt` |
| pycparser | 3.12 | BSD-3-Clause | https://github.com/eliben/pycparser | `pycparser-3.12.dist-info/licenses/LICENSE` |
| pycrashreport | 2.0.0 | GNU General Public License v3 or later (GPLv3+) | https://github.com/doronz88/pycrashreport | `pycrashreport-2.0.0.dist-info/licenses/LICENSE` |
| pycryptodome | 4.5.0 | BSD-2-Clause AND Unlicense AND MIT | https://www.pycryptodome.org | `pycryptodome-4.5.0.dist-info/licenses/LICENSE.rst`, `pycryptodome-4.5.0.dist-info/licenses/src/mldsa-native/LICENSE`, `pycryptodome-4.5.0.dist-info/licenses/src/mlkem-native/LICENSE` |
| pydantic | 2.14.3 | MIT | https://github.com/pydantic/pydantic | `pydantic-2.14.3.dist-info/licenses/LICENSE` |
| pydantic_core | 2.50.4 | MIT | https://github.com/pydantic | `pydantic_core-2.50.4.dist-info/licenses/LICENSE` |
| Pygments | 2.21.0 | BSD-2-Clause | https://pygments.org | `pygments-2.21.0.dist-info/licenses/AUTHORS`, `pygments-2.21.0.dist-info/licenses/LICENSE` |
| pygnuutils | 0.1.1 | GNU General Public License v3 or later (GPLv3+) | https://github.com/matan1008/pygnuutils | `pygnuutils-0.1.1.dist-info/LICENSE` |
| pyimg4 | 0.8.9 | MIT (from its licence file) | https://github.com/m1stadev/PyIMG4 | `pyimg4-0.8.9.dist-info/licenses/LICENSE` |
| pyiosbackup | 0.2.4 | GNU General Public License v3 or later (GPLv3+) | https://github.com/matan1008/pyiosbackup | `pyiosbackup-0.2.4.dist-info/licenses/LICENSE` |
| pykdebugparser | 1.10.0 | MIT (from its licence file) | https://github.com/matan1008/pykdebugparser | `pykdebugparser-1.10.0.dist-info/licenses/LICENSE` |
| pylzss | 0.3.9 | LGPL-3.0-only | https://github.com/m1stadev/pylzss | `pylzss-0.3.9.dist-info/licenses/COPYING`, `pylzss-0.3.9.dist-info/licenses/COPYING.LESSER` |
| pymobiledevice3 | 11.55.0 | GPL-3.0-or-later | https://github.com/doronz88/pymobiledevice3 | `pymobiledevice3-11.55.0.dist-info/licenses/LICENSE` |
| python-dateutil | 4.0.0 | BSD-3-Clause | https://github.com/dateutil/dateutil | `python_dateutil-4.0.0.dist-info/licenses/AUTHORS.md`, `python_dateutil-4.0.0.dist-info/licenses/LICENSE` |
| python-dotenv | 1.2.4 | BSD-3-Clause | https://github.com/theskumar/python-dotenv | `python_dotenv-1.2.4.dist-info/licenses/LICENSE` |
| python-pcapng | 2.1.1 | Apache-2.0 | https://github.com/rshk/python-pcapng | `python_pcapng-2.1.1.dist-info/LICENSE` |
| pytun-pmd3 | 3.0.3 | GNU General Public License v3 or later (GPLv3+) | https://github.com/doronz88/pytun-pmd3 | `pytun_pmd3-3.0.3.dist-info/licenses/LICENSE`, `pytun_pmd3/wintun/LICENSE.txt` |
| qh3 | 1.9.4 | BSD License | https://github.com/jawah/qh3 | `qh3-1.9.4.dist-info/licenses/LICENSE` |
| questionary | 2.1.1 | MIT | https://github.com/tmbo/questionary | `questionary-2.1.1.dist-info/LICENSE`, `questionary-2.1.1.dist-info/NOTICE` |
| remotezip2 | 0.0.2 | GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007 | https://github.com/doronz88/python-remotezip2 | `remotezip2-0.0.2.dist-info/LICENSE` |
| requests | 2.34.2 | Apache-2.0 | https://github.com/psf/requests | `requests-2.34.2.dist-info/licenses/LICENSE`, `requests-2.34.2.dist-info/licenses/NOTICE` |
| rich | 15.0.0 | MIT | https://github.com/Textualize/rich | `rich-15.0.0.dist-info/licenses/LICENSE` |
| shellingham | 1.5.4 | ISC License | https://github.com/sarugaku/shellingham | `shellingham-1.5.4.dist-info/LICENSE` |
| stack-data | 0.6.3 | MIT | http://github.com/alexmojaki/stack_data | `stack_data-0.6.3.dist-info/LICENSE.txt` |
| starlette | 1.10.0 | BSD-3-Clause | https://github.com/Kludex/starlette | `starlette-1.10.0.dist-info/licenses/LICENSE.md` |
| termcolor | 3.3.0 | MIT | https://github.com/termcolor/termcolor | `termcolor-3.3.0.dist-info/licenses/COPYING.txt` |
| traitlets | 5.16.1 | BSD License | https://github.com/ipython/traitlets | `traitlets-5.16.1.dist-info/licenses/LICENSE` |
| typer | 0.29.2 | MIT | https://github.com/fastapi/typer | `typer-0.29.2.dist-info/licenses/LICENSE`, `typer/_click/LICENSE.txt` |
| typer-injector | 0.3.0 | MIT | https://github.com/BenjyWiener/typer-injector | `typer_injector-0.3.0.dist-info/licenses/LICENSE.txt` |
| typing-inspection | 0.4.5 | MIT | https://github.com/pydantic/typing-inspection | `typing_inspection-0.4.5.dist-info/licenses/LICENSE` |
| typing_extensions | 4.16.0 | PSF-2.0 | https://github.com/python/typing_extensions | `typing_extensions-4.16.0.dist-info/licenses/LICENSE` |
| tzdata | 2026.6 | Apache-2.0 | https://github.com/python/tzdata | `tzdata-2026.6.dist-info/licenses/LICENSE`, `tzdata-2026.6.dist-info/licenses/licenses/LICENSE_APACHE` |
| urllib3 | 2.8.0 | MIT | https://github.com/urllib3/urllib3 | `urllib3-2.8.0.dist-info/licenses/LICENSE.txt` |
| uvicorn | 0.54.0 | BSD-3-Clause | https://uvicorn.dev/ | `uvicorn-0.54.0.dist-info/licenses/LICENSE.md` |
| wcwidth | 0.9.4 | MIT License | https://github.com/jquast/wcwidth | `wcwidth-0.9.4.dist-info/licenses/LICENSE` |
| wsproto | 1.3.2 | MIT | https://github.com/python-hyper/wsproto/ | `wsproto-1.3.2.dist-info/licenses/LICENSE` |
| xmltodict | 1.0.4 | MIT | https://github.com/martinblech/xmltodict | `xmltodict-1.0.4.dist-info/licenses/LICENSE` |
