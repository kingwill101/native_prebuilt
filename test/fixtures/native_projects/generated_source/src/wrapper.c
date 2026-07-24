#include "fixture.h"

/* External function from generated source */
extern int get_generated_value(void);

FIXTURE_EXPORT int native_prebuilt_fixture_add(int a, int b) {
  return a + b;
}

FIXTURE_EXPORT int native_prebuilt_fixture_generated(void) {
  return get_generated_value();
}
