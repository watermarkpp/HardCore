#pragma once
#include "core/object/ref_counted.h"
class Node;
class HardCoreMainSourceDeferred:public RefCounted {
 GDCLASS(HardCoreMainSourceDeferred,RefCounted);
 Ref<RefCounted> producer;String producer_path,producer_sha256;
 Dictionary validate_checkpoint(const Dictionary&,Node*,Node*,Node*)const;
 Dictionary observe_queue(const Dictionary&,Node*,Node*,Node*,bool);
protected:static void _bind_methods();
public:
 bool configure_original_checkpoint_producer(const Ref<RefCounted>&,const String&,const String&);
 Dictionary flush_original_main_source_checkpoint(const Dictionary&,Node*,Node*,Node*);
 Dictionary observe_original_main_source_receivers(const Dictionary&,Node*,Node*,Node*);
 Dictionary capabilities()const;
};
