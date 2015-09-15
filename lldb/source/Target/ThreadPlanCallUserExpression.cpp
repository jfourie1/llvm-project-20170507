//===-- ThreadPlanCallUserExpression.cpp ------------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "lldb/Target/ThreadPlanCallUserExpression.h"

// C Includes
// C++ Includes
// Other libraries and framework includes

// Project includes
#include "lldb/Breakpoint/Breakpoint.h"
#include "lldb/Breakpoint/BreakpointLocation.h"
#include "lldb/Core/Address.h"
#include "lldb/Core/Log.h"
#include "lldb/Core/Stream.h"
#include "lldb/Expression/UserExpression.h"
#include "lldb/Expression/IRDynamicChecks.h"
#include "lldb/Host/HostInfo.h"
#include "lldb/Target/LanguageRuntime.h"
#include "lldb/Target/Process.h"
#include "lldb/Target/RegisterContext.h"
#include "lldb/Target/StopInfo.h"
#include "lldb/Target/Target.h"
#include "lldb/Target/Thread.h"
#include "lldb/Target/ThreadPlanRunToAddress.h"

using namespace lldb;
using namespace lldb_private;

//----------------------------------------------------------------------
// ThreadPlanCallUserExpression: Plan to call a single function
//----------------------------------------------------------------------

ThreadPlanCallUserExpression::ThreadPlanCallUserExpression (Thread &thread,
                                                Address &function,
                                                llvm::ArrayRef<lldb::addr_t> args,
                                                const EvaluateExpressionOptions &options,
                                                lldb::UserExpressionSP &user_expression_sp) :
    ThreadPlanCallFunction (thread, function, CompilerType(), args, options),
    m_user_expression_sp (user_expression_sp)
{
    // User expressions are generally "User generated" so we should set them up to stop when done.
    SetIsMasterPlan (true);
    SetOkayToDiscard(false);
}

ThreadPlanCallUserExpression::~ThreadPlanCallUserExpression ()
{
}

void
ThreadPlanCallUserExpression::GetDescription (Stream *s, lldb::DescriptionLevel level)
{        
    if (level == eDescriptionLevelBrief)
        s->Printf("User Expression thread plan");
    else
        ThreadPlanCallFunction::GetDescription (s, level);
}

void
ThreadPlanCallUserExpression::WillPop ()
{
    ThreadPlanCallFunction::WillPop();
    if (m_user_expression_sp)
        m_user_expression_sp.reset();
}

bool
ThreadPlanCallUserExpression::MischiefManaged ()
{
    Log *log(lldb_private::GetLogIfAllCategoriesSet (LIBLLDB_LOG_STEP));

    if (IsPlanComplete())
    {
        if (log)
            log->Printf("ThreadPlanCallFunction(%p): Completed call function plan.",
                        static_cast<void*>(this));

        if (m_manage_materialization && PlanSucceeded() && m_user_expression_sp)
        {
            lldb::addr_t function_stack_top;
            lldb::addr_t function_stack_bottom;
            lldb::addr_t function_stack_pointer = GetFunctionStackPointer();

            function_stack_bottom = function_stack_pointer - HostInfo::GetPageSize();
            function_stack_top = function_stack_pointer;
            
            StreamString  error_stream;
            
            ExecutionContext exe_ctx(GetThread());

            m_user_expression_sp->FinalizeJITExecution(error_stream, exe_ctx, m_result_var_sp, function_stack_bottom, function_stack_top);
        }
        
        ThreadPlan::MischiefManaged ();
        return true;
    }
    else
    {
        return false;
    }
}

StopInfoSP
ThreadPlanCallUserExpression::GetRealStopInfo()
{
    StopInfoSP stop_info_sp = ThreadPlanCallFunction::GetRealStopInfo();
    
    if (stop_info_sp)
    {
        lldb::addr_t addr = GetStopAddress();
        DynamicCheckerFunctions *checkers = m_thread.GetProcess()->GetDynamicCheckers();
        StreamString s;
        
        if (checkers && checkers->DoCheckersExplainStop(addr, s))
            stop_info_sp->SetDescription(s.GetData());
    }

    return stop_info_sp;
}
