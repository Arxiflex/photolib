// The file manager's side of drag and drop with the Linux app over X11 (XDND 5), for its smoke test
// (app/integration_test/app_test.dart, ADR-0144); tools/smoke.sh builds it.
//   xdnd drop <pid> <uri>...     drops the URIs on the window of process <pid>; prints "finished" once it took them
//   xdnd catch <pid> <x> <y>     presses the mouse button at <x>,<y> of that window, drags 8 px, then onto a window
//                                of its own, releases it there and prints "dropped <uri-list>" for what arrived; then
//                                clicks <x>,<y> once more
// Exits 1 when nothing arrives within 10 s. XTest moves the pointer; it is loaded at run time, so only libX11 is
// needed to build this.
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <dlfcn.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static Display *dpy;
static Window root;
static Atom aware, enter, position, status, drop, finished, selection, copy, uri_list, wm_pid, property;
static int (*fake_button)(Display *, unsigned int, Bool, unsigned long);
static int (*fake_motion)(Display *, int, int, int, unsigned long);

// The top-level window of process pid that takes drops, below w.
static Window find(Window w, long pid) {
  Atom type;
  int format;
  unsigned long n, after;
  unsigned char *data = NULL;
  if (XGetWindowProperty(dpy, w, wm_pid, 0, 1, False, XA_CARDINAL, &type, &format, &n, &after, &data) == Success &&
      data != NULL) {
    long found = n == 1 ? *(long *)data : 0;
    XFree(data);
    data = NULL;
    if (found == pid && XGetWindowProperty(dpy, w, aware, 0, 1, False, XA_ATOM, &type, &format, &n, &after,
                                           &data) == Success && data != NULL) {
      XFree(data);
      return w;
    }
  }
  Window top, parent, *children = NULL, hit = None;
  unsigned int count = 0;
  if (XQueryTree(dpy, w, &top, &parent, &children, &count)) {
    for (unsigned int i = 0; i < count && hit == None; i++) hit = find(children[i], pid);
    XFree(children);
  }
  return hit;
}

static void message(Window to, Atom type, long l0, long l1, long l2, long l3, long l4) {
  XEvent e;
  memset(&e, 0, sizeof e);
  e.xclient.type = ClientMessage;
  e.xclient.window = to;
  e.xclient.message_type = type;
  e.xclient.format = 32;
  e.xclient.data.l[0] = l0;
  e.xclient.data.l[1] = l1;
  e.xclient.data.l[2] = l2;
  e.xclient.data.l[3] = l3;
  e.xclient.data.l[4] = l4;
  XSendEvent(dpy, to, False, NoEventMask, &e);
  XFlush(dpy);
}

// The next event before the deadline; 0 once it has passed.
static int next(XEvent *e, time_t deadline) {
  while (!XPending(dpy)) {
    if (time(NULL) > deadline) return 0;
    struct pollfd p = {ConnectionNumber(dpy), POLLIN, 0};
    poll(&p, 1, 50);
  }
  XNextEvent(dpy, e);
  return 1;
}

static void move(int x, int y) {
  fake_motion(dpy, -1, x, y, CurrentTime);
  XSync(dpy, False);
  usleep(50000);
}

static void button(Bool down) {
  fake_button(dpy, 1, down, CurrentTime);
  XSync(dpy, False);
  usleep(50000);
}

static int drop_on(Window target, char **uris, int n) {
  size_t length = 1;
  for (int i = 0; i < n; i++) length += strlen(uris[i]) + 2;
  char *list = calloc(length, 1);
  for (int i = 0; i < n; i++) strcat(strcat(list, uris[i]), "\r\n");
  Window source = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
  XSetSelectionOwner(dpy, selection, source, CurrentTime);
  XWindowAttributes a;
  XGetWindowAttributes(dpy, target, &a);
  int x, y;
  Window child;
  XTranslateCoordinates(dpy, target, root, a.width / 2, a.height / 2, &x, &y, &child);
  message(target, enter, (long)source, 5L << 24, (long)uri_list, None, None);
  message(target, position, (long)source, 0, ((long)x << 16) | y, CurrentTime, (long)copy);
  XEvent e;
  int dropped = 0;
  for (time_t deadline = time(NULL) + 10; next(&e, deadline);) {
    if (e.type == ClientMessage && e.xclient.message_type == status && !dropped) {
      if (!(e.xclient.data.l[1] & 1)) {
        fprintf(stderr, "xdnd: the window refused the drop\n");
        return 1;
      }
      message(target, drop, (long)source, 0, CurrentTime, 0, 0);
      dropped = 1;
    } else if (e.type == SelectionRequest) {
      XSelectionRequestEvent *r = &e.xselectionrequest;
      XEvent reply;
      memset(&reply, 0, sizeof reply);
      reply.xselection.type = SelectionNotify;
      reply.xselection.requestor = r->requestor;
      reply.xselection.selection = r->selection;
      reply.xselection.target = r->target;
      reply.xselection.time = r->time;
      if (r->target == uri_list) {
        XChangeProperty(dpy, r->requestor, r->property, uri_list, 8, PropModeReplace, (unsigned char *)list,
                        (int)strlen(list));
        reply.xselection.property = r->property;
      }
      XSendEvent(dpy, r->requestor, False, NoEventMask, &reply);
      XFlush(dpy);
    } else if (e.type == ClientMessage && e.xclient.message_type == finished) {
      puts("finished");
      return 0;
    }
  }
  fprintf(stderr, "xdnd: no answer to the drop\n");
  return 1;
}

static int catch_from(Window app, int x, int y) {
  XWindowAttributes a;
  XGetWindowAttributes(dpy, app, &a);
  int ax, ay;
  Window child;
  XTranslateCoordinates(dpy, app, root, 0, 0, &ax, &ay, &child);
  // A window of its own, over the far corner of the app's.
  XSetWindowAttributes attributes = {.override_redirect = True};
  const int wx = ax + a.width - 120, wy = ay + a.height - 120;
  Window w = XCreateWindow(dpy, root, wx, wy, 100, 100, 0, CopyFromParent, InputOutput, CopyFromParent,
                           CWOverrideRedirect, &attributes);
  long version = 5;
  XChangeProperty(dpy, w, aware, XA_ATOM, 32, PropModeReplace, (unsigned char *)&version, 1);
  XMapRaised(dpy, w);
  XSync(dpy, False);
  move(ax + x, ay + y);
  button(True);
  for (int i = 1; i <= 8; i++) move(ax + x + i, ay + y);
  usleep(500000);
  for (int i = 1; i <= 10; i++) move(ax + x + (wx + 50 - ax - x) * i / 10, ay + y + (wy + 50 - ay - y) * i / 10);
  XEvent e;
  Window source = None;
  for (time_t deadline = time(NULL) + 10; next(&e, deadline);) {
    if (e.type == ClientMessage && e.xclient.message_type == position) {
      source = (Window)e.xclient.data.l[0];
      message(source, status, (long)w, 1, 0, 0, (long)copy);
      button(False);
    } else if (e.type == ClientMessage && e.xclient.message_type == drop) {
      XConvertSelection(dpy, selection, uri_list, property, w, (Time)e.xclient.data.l[2]);
      XFlush(dpy);
    } else if (e.type == SelectionNotify) {
      Atom type;
      int format;
      unsigned long n, after;
      unsigned char *data = NULL;
      if (e.xselection.property != None &&
          XGetWindowProperty(dpy, w, property, 0, 65536, True, AnyPropertyType, &type, &format, &n, &after,
                             &data) == Success && data != NULL) {
        printf("dropped %s\n", data);
        XFree(data);
      }
      message(source, finished, (long)w, 1, (long)copy, 0, 0);
      fflush(stdout);
      // A click on the app a moment later, as a person's would come, which it hears only if it knows the button went
      // up after the drag.
      usleep(500000);
      move(ax + x, ay + y);
      button(True);
      button(False);
      return 0;
    }
  }
  fprintf(stderr, "xdnd: nothing was dropped\n");
  return 1;
}

int main(int argc, char **argv) {
  if (argc < 4 || (strcmp(argv[1], "drop") != 0 && strcmp(argv[1], "catch") != 0)) {
    fprintf(stderr, "usage: xdnd drop <pid> <uri>... | xdnd catch <pid> <x> <y>\n");
    return 2;
  }
  void *xtst = dlopen("libXtst.so.6", RTLD_NOW);
  dpy = XOpenDisplay(NULL);
  if (dpy == NULL || xtst == NULL) {
    fprintf(stderr, "xdnd: no X display or no libXtst.so.6\n");
    return 1;
  }
  *(void **)&fake_button = dlsym(xtst, "XTestFakeButtonEvent");
  *(void **)&fake_motion = dlsym(xtst, "XTestFakeMotionEvent");
  root = DefaultRootWindow(dpy);
  aware = XInternAtom(dpy, "XdndAware", False);
  enter = XInternAtom(dpy, "XdndEnter", False);
  position = XInternAtom(dpy, "XdndPosition", False);
  status = XInternAtom(dpy, "XdndStatus", False);
  drop = XInternAtom(dpy, "XdndDrop", False);
  finished = XInternAtom(dpy, "XdndFinished", False);
  selection = XInternAtom(dpy, "XdndSelection", False);
  copy = XInternAtom(dpy, "XdndActionCopy", False);
  uri_list = XInternAtom(dpy, "text/uri-list", False);
  wm_pid = XInternAtom(dpy, "_NET_WM_PID", False);
  property = XInternAtom(dpy, "XDND_DATA", False);
  Window app = None;
  for (int i = 0; i < 100 && app == None; i++) {
    app = find(root, atol(argv[2]));
    if (app == None) usleep(100000);
  }
  if (app == None) {
    fprintf(stderr, "xdnd: process %s has no window that takes drops\n", argv[2]);
    return 1;
  }
  return strcmp(argv[1], "drop") == 0 ? drop_on(app, argv + 3, argc - 3)
                                      : catch_from(app, atoi(argv[3]), argc > 4 ? atoi(argv[4]) : 0);
}
