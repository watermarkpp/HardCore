#pragma once
#include <cstddef>
#include <string>
namespace hardcore::simulation {
enum class SourceAdmissionOpcode{UNSELECTED,PREPARE,COMMIT,ABORT,LOADING,PINS,RELEASE_PINS,INVALID};
inline SourceAdmissionOpcode source_admission_opcode(const std::string&name){
 if(name=="feature.source_admission_unselected")return SourceAdmissionOpcode::UNSELECTED;
 if(name=="feature.source_admission_prepare")return SourceAdmissionOpcode::PREPARE;
 if(name=="feature.source_admission_commit")return SourceAdmissionOpcode::COMMIT;
 if(name=="feature.source_admission_abort")return SourceAdmissionOpcode::ABORT;
 if(name=="feature.source_admission_loading")return SourceAdmissionOpcode::LOADING;
 if(name=="feature.source_admission_pins")return SourceAdmissionOpcode::PINS;
 if(name=="feature.source_admission_release_pins")return SourceAdmissionOpcode::RELEASE_PINS;
 return SourceAdmissionOpcode::INVALID;
}
inline std::size_t source_admission_arity(SourceAdmissionOpcode op){return op==SourceAdmissionOpcode::INVALID?0:op==SourceAdmissionOpcode::PREPARE?3:op==SourceAdmissionOpcode::COMMIT?2:1;}
}
