echo "{| border='1' align='right' style='text-align:center;'"
echo "!Package"
echo "!Current Version"
echo "!Upstream Version"
echo "|-"

for package in *; do
	if [ -d "$package" ]; then
		source $package/PKGBUILD

    echo "|$package"
    echo "|$pkgver"
    echo "|"
    echo "|-"
	fi
done

echo "|"
echo "|"
echo "|"
echo "|}"
