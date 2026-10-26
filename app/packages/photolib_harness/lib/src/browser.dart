/// Outside a browser there is no page to watch.
void Function() installBrowser(void Function(String problem) report) =>
    _nothing;

void _nothing() {}
